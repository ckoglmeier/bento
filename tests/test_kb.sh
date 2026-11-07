#!/bin/zsh
# Exercises kb against a throwaway workspace and throwaway repos, never the real ones.
KB="${0:A:h:h}/kb"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export BENTO_HOME="$T/home"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
check() { if [[ "$2" == *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1"; echo "     wanted: $3"; echo "     got: $2"; fail=1; fi; }
checkn() { if [[ "$2" != *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1 (should not contain $3)"; echo "     got: $2"; fail=1; fi; }

# Two fake products: one bare remote plus a clone and a worktree; one with no remote.
git init -q --bare -b main "$T/alpha.git"
git init -q -b main "$T/alpha"; cd "$T/alpha"
mkdir -p docs/qa; printf '# Alpha backlog\n\n## Release 1\n\n| Order | Work | Done when |\n| --- | --- | --- |\n| F1 | Build it | It works |\n' > docs/BACKLOG.md
printf '# QA\n' > docs/qa/one.md; printf '# Roadmap\n' > ROADMAP.md; printf 'code\n' > app.py
git add -A; git commit -qm init; git remote add origin "$T/alpha.git"; git push -q origin main; git remote set-head origin main 2>/dev/null
git worktree add -q -b feature "$T/alpha-wt"
printf '# stale branch copy\n' > "$T/alpha-wt/docs/BACKLOG.md"
mkdir -p "$T/beta/docs"; printf '# Beta\n' > "$T/beta/docs/notes.md"

cd "$T"
check "init" "$("$KB" init "$BENTO_HOME" --owner sam 2>&1)" "workspace ready"
check "connect with import" "$("$KB" connect "$T/alpha" --import-docs)" "Imported 3 docs"
check "connect from a plain folder" "$(cd "$T/beta" && "$KB" connect --name beta)" "Connected beta"
check "imports default branch, not worktree" "$(cat "$BENTO_HOME/products/alpha/docs/BACKLOG.md")" "Alpha backlog"
check "no code imported" "$(ls -R "$BENTO_HOME/products/alpha")" "SOURCE.md"
checkn "no code imported 2" "$(ls -R "$BENTO_HOME/products/alpha")" "app.py"
[[ ! -e "$T/alpha/.bento" && -z "$(git -C "$T/alpha" status --porcelain)" ]] && echo "ok   connect adds nothing to the repo" || { echo "FAIL repo touched"; fail=1; }
check "projects lists both" "$("$KB" projects)" "beta"
check "worktree detected by remote" "$(cd "$T/alpha-wt" && "$KB" projects)" "* alpha"
check "plain folder detected by path" "$(cd "$T/beta" && "$KB" projects)" "* beta"
checkn "unconnected folder detected as nothing" "$(cd /tmp && "$KB" projects)" "*"

cd "$T/alpha-wt"
check "add defaults project from folder" "$("$KB" add 'F1 Build it' --to next --source docs/BACKLOG.md#release-1 --done-when works)" "(alpha)"
check "source resolved" "$("$KB" show 1)" "source: products/alpha/docs/BACKLOG.md#release-1"
check "bad source refused" "$("$KB" add x --source docs/NOPE.md 2>&1)" "No doc at"
check "doc outside workspace refused" "$("$KB" add x --source ../../../../etc/hosts.md 2>&1)" "No doc at"
"$KB" add "F2 Other" --to next --for codex >/dev/null
(cd "$T/beta" && "$KB" add "Beta epic" --to next >/dev/null)
"$KB" add "Test F1 and F2" --kind testing --verifies 1,2 --to next >/dev/null
check "bad kind refused" "$("$KB" add x --kind nope 2>&1)" "Kind must be"

check "next scoped to this project" "$("$KB" next --as claude)" "in alpha"
check "next from beta sees beta" "$(cd "$T/beta" && "$KB" next --as claude)" "Beta epic"
check "next all projects" "$("$KB" next --as claude --all-projects)" "F1 Build it"
check "list across projects" "$("$KB")" "Beta epic"
checkn "list filtered to a project" "$("$KB" -p alpha)" "Beta epic"
check "list filtered by kind" "$("$KB" --kind testing)" "Test F1 and F2"
checkn "list filtered by kind 2" "$("$KB" --kind testing)" "F1 Build it"

check "testing waits for build" "$("$KB" claim 4 --as claude --also 2>&1)" "nothing to test until"
check "plan created" "$("$KB" plan implementation 'Free Beta!' --epics 1 2)" "implementation-free-beta.md"
check "plan lists epics" "$(cat "$BENTO_HOME/products/alpha/plans/implementation-free-beta.md")" "#1 F1 Build it"
check "plan linked to card" "$("$KB" show 2)" "plan: products/alpha/plans/implementation-free-beta.md"
check "duplicate plan refused" "$("$KB" plan implementation 'Free Beta!' 2>&1)" "already exists"
check "plan needs a project" "$(cd /tmp && "$KB" plan release x 2>&1)" "Which project"
check "docs lists plan" "$("$KB" docs)" "plans/implementation-free-beta.md"

P=products/alpha/plans/implementation-free-beta.md
check "handoff" "$("$KB" handoff 1 2 --to claude --plan $P --as codex)" "Handed #1, #2 to claude"
check "handoff sets target" "$("$KB" show 2)" "for: claude"
check "handoff keeps order at top" "$("$KB" --json | python3 -c "import json,sys; d=json.load(sys.stdin); print([c['id'] for c in [x for x in d['columns'] if x['name']=='Next'][0]['cards']][:2])")" "[1, 2]"
check "other agent can't take handed card" "$("$KB" claim 1 --as codex 2>&1)" "for claude"
check "claim a set" "$("$KB" claim 1 2 --as claude)" "#2 F2 Other"
check "claim shows plan" "$("$KB" show 1)" "claimed: claude"
check "testing still waits on review" "$("$KB" next --as codex)" "reach"
check "review" "$("$KB" review 1 --as claude --note done)" "in Review"
"$KB" review 2 --as claude >/dev/null
check "testing ready after review" "$("$KB" next --as codex)" "Test F1 and F2"
check "archive keeps ids" "$("$KB" move 1 done >/dev/null; "$KB" archive; "$KB" add after)" "Added #5"

# The scratchpad is ignored by agents.
"$KB" add "Call the plumber" --to scratchpad --for sam -p "" >/dev/null
checkn "scratchpad not offered to agents" "$("$KB" next --as codex --all-projects)" "plumber"

# Hand edits survive.
printf '\n## Parking\n\n### Handwritten card\n- for: sam\n\n```\n## not a column\n```\n' >> "$BENTO_HOME/BOARD.md"
"$KB" note 3 x >/dev/null
check "extra column and fence kept" "$(cat "$BENTO_HOME/BOARD.md")" "## not a column"
check "handwritten numbered" "$(cat "$BENTO_HOME/BOARD.md")" "### #7 Handwritten card"

# Race across real processes.
export BENTO_HOME="$T/race"; mkdir -p "$BENTO_HOME"; printf '# Board\n\n## Next\n\n' > "$BENTO_HOME/BOARD.md"
for i in {1..10}; do "$KB" add "card $i" --to next -p x >/dev/null; done
for i in {1..40}; do ("$KB" claim --as "agent$i" --all-projects >/dev/null 2>&1) & done
wait
claims=$(grep -c '^- claimed:' "$BENTO_HOME/BOARD.md"); uniq=$(grep '^- claimed:' "$BENTO_HOME/BOARD.md" | sort -u | wc -l | tr -d ' ')
[[ "$claims" == 10 && "$uniq" == 10 ]] && echo "ok   race: 10 distinct claims" || { echo "FAIL race claims=$claims uniq=$uniq"; fail=1; }

# Web server.
export BENTO_HOME="$T/home"
"$KB" serve --port 47471 --no-open >/dev/null 2>&1 &
SP=$!
sleep 1
U=http://127.0.0.1:47471; J='Content-Type: application/json'
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
check "page" "$(curl -s $U/)" "<title>Bento</title>"
check "board has projects" "$(curl -s $U/api/board)" '"owner": "sam"'
check "docs api" "$(curl -s $U/api/docs)" "implementation-free-beta.md"
check "doc read" "$(curl -s "$U/api/doc?path=products/alpha/docs/BACKLOG.md")" "Alpha backlog"
check "doc has a Codex link" "$(curl -s "$U/api/doc?path=products/alpha/docs/BACKLOG.md")" "codex://threads/new?path="
check "doc has a Claude link" "$(curl -s "$U/api/doc?path=products/alpha/docs/BACKLOG.md")" '"claude": "claude'
check "link prompt names the doc" "$(curl -s "$U/api/doc?path=products/alpha/docs/BACKLOG.md")" "products%2Falpha%2Fdocs%2FBACKLOG.md"
check "doc traversal refused" "$(code "$U/api/doc?path=../../../../../etc/hosts")" "404"
check "non-doc refused" "$(code "$U/api/doc?path=bento.json")" "404"
check "bad host refused" "$(code -H 'Host: evil.example' $U/api/board)" "403"
check "cross-site post refused" "$(code -H 'Origin: https://evil.example' -H "$J" -d '{}' $U/api/archive)" "403"
check "non-json post refused" "$(code -d '{}' $U/api/archive)" "403"
"$KB" add "Plan card" -p alpha --plan $P >/dev/null
check "changes need a comment" "$(code -H "$J" -d "{\"plan\":\"$P\",\"decision\":\"changes\"}" $U/api/review)" "400"
check "request changes" "$(code -H "$J" -d "{\"plan\":\"$P\",\"decision\":\"changes\",\"comment\":\"more detail\"}" $U/api/review)" "200"
check "changes block the card" "$("$KB" show 8)" "blocked: changes requested: more detail"
check "approve" "$(code -H "$J" -d "{\"plan\":\"$P\",\"decision\":\"approve\"}" $U/api/review)" "200"
check "approve clears the block" "$("$KB" show 8)" "approved: sam"
checkn "approve clears the block 2" "$("$KB" show 8)" "blocked:"
check "stale edit refused" "$(code -H "$J" -d '{"id":8,"title":"x","body":"","base_body":"old","base_title":"Plan card"}' $U/api/edit)" "409"
kill $SP

# Agent setup writes only marked blocks and is repeatable.
FAKE="$T/fakehome"; mkdir -p "$FAKE/.codex" "$FAKE/.claude"
printf '# Mine\n\nKeep this.\n' > "$FAKE/.codex/AGENTS.md"; printf 'model = "x"\n' > "$FAKE/.codex/config.toml"
HOME="$FAKE" "$KB" install-agents >/dev/null; HOME="$FAKE" "$KB" install-agents >/dev/null
check "existing instructions kept" "$(cat "$FAKE/.codex/AGENTS.md")" "Keep this."
[[ $(grep -c 'bento:start' "$FAKE/.codex/AGENTS.md") == 1 ]] && echo "ok   block not duplicated" || { echo "FAIL duplicated block"; fail=1; }
[[ $(grep -c 'writable_roots' "$FAKE/.codex/config.toml") == 1 ]] && echo "ok   codex root added once" || { echo "FAIL codex root"; fail=1; }
check "owner in block" "$(cat "$FAKE/.claude/CLAUDE.md")" "sam, Claude and Codex"
check "rules fill in owner" "$("$KB" rules)" "for sam, Claude and Codex"
ls -a "$BENTO_HOME" | grep -q '^\.kb-' && { echo "FAIL temp files left"; fail=1; } || echo "ok   no temp files left"

# Push and push back.
export BENTO_HOME="$T/notify"
"$KB" init "$BENTO_HOME" --owner sam >/dev/null
SENT="$T/sent.txt"; : > "$SENT"
python3 -c "
import json,os,sys
p=os.environ['BENTO_HOME']+'/bento.json'; c=json.load(open(p))
c['notify']={'command':'printf \"%s\\\\n\" \"\$BENTO_MESSAGE\" >> \"$SENT\"'}
json.dump(c,open(p,'w'))"
"$KB" serve --port 47470 --no-open >/dev/null 2>&1 &
S1=$!
"$KB" serve --port 47469 --no-open >/dev/null 2>&1 &
S2=$!
sleep 1
check "second serve on a used port just reports" "$("$KB" serve --port 47470 --no-open)" "already running"
curl -sN --max-time 3 http://127.0.0.1:47470/api/stream > "$T/stream.txt" &
CURL=$!
sleep 0.5
"$KB" add "Pushed epic" -p x >/dev/null
check "push moves to Next" "$("$KB" push 1 --to codex --as sam)" "Handed #1 to codex"
start=$SECONDS
("$KB" wait 1 > "$T/wait.txt"; echo "code=$?" >> "$T/wait.txt") &
WAITER=$!
sleep 0.5
"$KB" claim 1 --as codex >/dev/null
"$KB" review 1 --as codex --note "shipped" >/dev/null
wait $WAITER
(( SECONDS - start < 3 )) && echo "ok   wait woke straight away" || { echo "FAIL wait was slow"; fail=1; }
check "wait returns the result" "$(cat "$T/wait.txt")" "shipped"
check "wait exits 0" "$(cat "$T/wait.txt")" "code=0"
wait $CURL
check "web board gets a live message" "$(cat "$T/stream.txt")" "data: change"
sleep 0.5
check "agent finishing notifies the owner" "$(cat "$SENT")" "#1 Pushed epic is ready for review"
[[ $(grep -c 'ready for review' "$SENT") == 1 ]] && echo "ok   two servers deliver once" || { echo "FAIL duplicate delivery"; cat "$SENT"; fail=1; }
"$KB" move 1 done --as sam >/dev/null; sleep 0.5
checkn "owner's own moves stay quiet" "$(cat "$SENT")" "is done"
"$KB" add "Stuck epic" -p x --to next >/dev/null
"$KB" block 2 "need a key"; sleep 0.5
check "blocked notifies" "$(cat "$SENT")" "#2 Stuck epic needs you: need a key"
"$KB" wait 2 >/dev/null; check "wait exits 2 when blocked" "$?" "2"
"$KB" unblock 2 >/dev/null
"$KB" wait 2 --timeout 1 >/dev/null; check "wait exits 3 on timeout" "$?" "3"
"$KB" archive >/dev/null
"$KB" wait 1 >/dev/null; check "wait sees archived as finished" "$?" "0"
"$KB" wait 99 >/dev/null 2>&1; check "wait refuses unknown card" "$?" "1"

# Waking a Codex session: once for the whole set, not for its own actions.
FAKEBIN="$T/bin"; mkdir -p "$FAKEBIN"; WOKE="$T/woke.txt"; : > "$WOKE"
printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$(pwd -P)" "$*" >> "%s"\n' "$WOKE" > "$FAKEBIN/codex"; chmod +x "$FAKEBIN/codex"
kill $S1 $S2; sleep 0.3
PATH="$FAKEBIN:$PATH" "$KB" serve --port 47470 --no-open >/dev/null 2>&1 &
S1=$!
sleep 1
"$KB" add "Set A" -p x >/dev/null; "$KB" add "Set B" -p x >/dev/null
cd "$T/beta"
check "codex push registers its session" "$(env -u CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID=thread-1 "$KB" push 3 4 --to claude --as codex)" "will be resumed"
check "claude push suggests wait" "$(env -u CODEX_THREAD_ID CLAUDE_CODE_SESSION_ID=abc "$KB" add 'Set C' -p x >/dev/null; env -u CODEX_THREAD_ID CLAUDE_CODE_SESSION_ID=abc "$KB" push 5 --to codex --as claude)" "kb wait 5"
cd "$T"
"$KB" claim 3 --as claude --also >/dev/null; "$KB" review 3 --as claude >/dev/null; sleep 0.7
[[ ! -s "$WOKE" ]] && echo "ok   no wake until the whole set is finished" || { echo "FAIL woke early"; fail=1; }
"$KB" block 4 "need a call"; sleep 0.7
check "blocked wakes right away" "$(cat "$WOKE")" "#4 Set B is blocked: need a call"
check "wake targets the right session" "$(cat "$WOKE")" "resume thread-1"
check "wake runs in the session folder" "$(cat "$WOKE")" "$(cd "$T/beta" && pwd -P)|"
: > "$WOKE"; "$KB" unblock 4 >/dev/null; "$KB" claim 4 --as claude --also >/dev/null; "$KB" review 4 --as claude >/dev/null; sleep 0.7
check "finished set wakes the session" "$(cat "$WOKE")" "#3 Set A; #4 Set B finished"
[[ $(wc -l < "$WOKE" | tr -d ' ') == 1 ]] && echo "ok   wakes once" || { echo "FAIL multiple wakes"; cat "$WOKE"; fail=1; }
: > "$WOKE"; env -u CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID=thread-2 "$KB" add "Own" -p x >/dev/null; N=6
env -u CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID=thread-2 "$KB" push $N --to codex --as codex >/dev/null
env -u CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID=thread-2 "$KB" claim $N --as codex --also >/dev/null
env -u CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID=thread-2 "$KB" review $N --as codex >/dev/null; sleep 0.7
[[ ! -s "$WOKE" ]] && echo "ok   a session isn't woken by its own actions" || { echo "FAIL self wake"; cat "$WOKE"; fail=1; }

# Calendar and tracking.
"$KB" add "Old name check" -p x --to desk >/dev/null
check "desk still works as an alias" "$(grep -c '^## Desk' "$BENTO_HOME/BOARD.md"; grep -c '^## Scratchpad' "$BENTO_HOME/BOARD.md")" "1"
check "bad date refused" "$("$KB" add x --target soon 2>&1)" "Dates look like"
TODAY=$(date +%F); SOON=$(date -v+3d +%F); FAR=$(date -v+60d +%F); PAST=$(date -v-2d +%F)
"$KB" add "Dep build" -p cal --kind milestone --target "$FAR" >/dev/null; DEP=$("$KB" --json | python3 -c "import json,sys;d=json.load(sys.stdin);print([c['id'] for x in d['columns'] for c in x['cards'] if c['title']=='Dep build'][0])")
"$KB" add "Dep test" -p cal --kind testing --verifies $DEP >/dev/null; T2=$((DEP+1))
"$KB" add "Ship it" -p cal --kind release --needs $T2 --target "$(date -v+30d +%F)" >/dev/null; REL=$((DEP+2))
check "dependency dated later is at risk" "$("$KB" calendar -p cal)" "at risk, 0 of 2 dependencies done  #$DEP is dated after this"
check "dependencies are transitive" "$("$KB" calendar -p cal)" "#$DEP Dep build: Milestones"
"$KB" set $REL target "$SOON" >/dev/null; "$KB" set $DEP target >/dev/null
check "open deps close to the date are at risk" "$("$KB" calendar -p cal)" "2 dependencies are open with 3 days left"
"$KB" set $REL target "$PAST" >/dev/null
check "past date is late" "$("$KB" calendar -p cal)" "late"
"$KB" set $REL target "$FAR" >/dev/null
check "far date with open deps is on track" "$("$KB" calendar -p cal)" "on track"
"$KB" block $DEP "waiting" >/dev/null
check "blocked dep is at risk" "$("$KB" calendar -p cal)" "#$DEP is blocked"
"$KB" unblock $DEP >/dev/null; "$KB" set $REL target >/dev/null
check "undated release listed" "$("$KB" calendar -p cal)" "no date"
check "plain epics can't take a date" "$("$KB" add "Plain" -p cal --target "$FAR" 2>&1)" "Dates belong on milestones"
PLAIN=$("$KB" add "Plain epic" -p cal | sed -E 's/Added #([0-9]+).*/\1/')
check "plain epics can't be given a date" "$("$KB" set $PLAIN target "$FAR" 2>&1)" "Dates belong on milestones"
check "date api refuses plain epics" "$(code -H 'Content-Type: application/json' -d "{\"id\":$PLAIN,\"field\":\"target\",\"value\":\"$FAR\"}" http://127.0.0.1:47470/api/set)" "400"
check "milestone lands in its column" "$("$KB" add "Launch day" -p cal --kind milestone)" "to Milestones"
checkn "milestones aren't offered as work" "$("$KB" next --as codex --all-projects)" "Launch day"
"$KB" move $REL done >/dev/null; check "finished release is reached" "$("$KB" calendar -p cal)" "reached"; "$KB" move $REL backlog >/dev/null
"$KB" set $REL theme "Pay without friction" >/dev/null
check "theme shows on the calendar" "$("$KB" calendar -p cal)" "Theme: Pay without friction"
check "milestone doc api" "$(curl -s -H 'Content-Type: application/json' -d "{\"id\":$REL}" http://127.0.0.1:47470/api/milestone-doc)" "plans/release-ship-it.md"
check "doc linked to the milestone" "$("$KB" calendar -p cal)" "Doc: products/cal/plans/release-ship-it.md"
check "second request reuses the doc" "$(curl -s -H 'Content-Type: application/json' -d "{\"id\":$REL}" http://127.0.0.1:47470/api/milestone-doc)" "plans/release-ship-it.md"
check "milestone doc lists its dependencies" "$(cat "$BENTO_HOME/products/cal/plans/release-ship-it.md")" "Dep test"
checkn "milestone doc doesn't list itself" "$(cat "$BENTO_HOME/products/cal/plans/release-ship-it.md")" "#$REL "
check "release doc has its sections" "$(cat "$BENTO_HOME/products/cal/plans/release-ship-it.md")" "## Release notes"
check "milestone doc has acceptance criteria" "$("$KB" plan milestone "Launch day" -p cal; cat "$BENTO_HOME/products/cal/plans/milestone-launch-day.md")" "## Acceptance criteria"
check "plain epics don't get a milestone doc" "$(code -H 'Content-Type: application/json' -d "{\"id\":$PLAIN}" http://127.0.0.1:47470/api/milestone-doc)" "400"
check "bad date refused by set" "$("$KB" set $REL target tomorrow 2>&1)" "Dates look like"
check "target api" "$(code -H 'Content-Type: application/json' -d "{\"id\":$REL,\"field\":\"target\",\"value\":\"$FAR\"}" http://127.0.0.1:47470/api/set)" "200"
check "target api refuses other fields" "$(code -H 'Content-Type: application/json' -d "{\"id\":$REL,\"field\":\"for\",\"value\":\"x\"}" http://127.0.0.1:47470/api/set)" "400"
check "board data has tracking" "$(curl -s http://127.0.0.1:47470/api/board)" '"tracking"'
check "writing kind allowed" "$("$KB" plan writing 'Launch essay' -p cal)" "writing-launch-essay.md"

# Scratchpad: notes and ideas are one thing.
check "scratchpad note saved" "$("$KB" add "Big idea" --to scratchpad -p ideas)" "to Scratchpad"
IDEA=$("$KB" --json | python3 -c "import json,sys;d=json.load(sys.stdin);print([c['id'] for x in d['columns'] for c in x['cards'] if c['title']=='Big idea'][0])")
check "scratchpad note belongs to the owner" "$("$KB" show $IDEA)" "for: sam"
check "idea isn't a kind" "$("$KB" add x --kind idea 2>&1)" "Kind must be"
checkn "scratchpad isn't offered as work" "$("$KB" next --as codex --all-projects)" "Big idea"
"$KB" set $IDEA kind idea >/dev/null; "$KB" move $IDEA backlog >/dev/null
checkn "promoting clears any old label" "$("$KB" show $IDEA)" "kind: idea"
check "promoted note is for anyone" "$("$KB" show $IDEA)" "for: any"

# Delete and restore.
ID0=$("$KB" add "Base epic" -p del | sed -E 's/Added #([0-9]+).*/\1/'); ID1=$((ID0+1))
"$KB" add "Waits on base" -p del --needs $ID0 >/dev/null
env -u CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID=thread-9 "$KB" wake $ID0 $ID1 >/dev/null
: > "$WOKE"
check "delete" "$("$KB" delete $ID0)" "kb restore $ID0"
check "deleted card leaves the board" "$("$KB" show $ID0 2>&1)" "No card"
checkn "dependents are cleared" "$("$KB" show $ID1)" "needs:"
check "trash keeps it" "$(cat "$BENTO_HOME/TRASH.md")" "Base epic"
sleep 0.5
[[ ! -s "$WOKE" ]] && echo "ok   deleting doesn't falsely wake a session" || { echo "FAIL false wake"; cat "$WOKE"; fail=1; }
check "wake list drops the card" "$(cat "$BENTO_HOME/.notify.wake.json")" "$ID1"
checkn "wake list drops the card 2" "$(python3 -c "import json;print([w['ids'] for w in json.load(open('$BENTO_HOME/.notify.wake.json'))])")" "$ID0,"
ID2=$("$KB" add "After delete" -p del | sed -E 's/Added #([0-9]+).*/\1/')
(( ID2 > ID1 )) && echo "ok   deleted ids aren't reused" || { echo "FAIL id reuse $ID2"; fail=1; }
check "restore" "$("$KB" restore $ID0)" "to Backlog"
check "restored card is back" "$("$KB" show $ID0)" "Base epic"
checkn "restored card left the trash" "$(cat "$BENTO_HOME/TRASH.md")" "Base epic"
check "restore unknown refused" "$("$KB" restore 9999 2>&1)" "No card #9999"
check "delete unknown refused" "$("$KB" delete 9999 2>&1)" "No card"
check "delete api" "$(code -H 'Content-Type: application/json' -d "{\"id\":$ID2}" http://127.0.0.1:47470/api/delete)" "200"
check "delete api needs json" "$(code -d "{\"id\":$ID0}" http://127.0.0.1:47470/api/delete)" "403"
check "delete api refuses other sites" "$(code -H 'Origin: https://evil.example' -H 'Content-Type: application/json' -d "{\"id\":$ID0}" http://127.0.0.1:47470/api/delete)" "403"
"$KB" delete $ID1 >/dev/null; "$KB" delete $ID0 >/dev/null

# Saving docs from the board.
mkdir -p "$BENTO_HOME/products/ed/docs"; printf 'old\n' > "$BENTO_HOME/products/ed/docs/note.md"; printf 'secret\n' > "$T/outside.md"
SAVE=http://127.0.0.1:47470/api/doc-save; JH='Content-Type: application/json'
check "doc saves" "$(code -H "$JH" -d '{"path":"products/ed/docs/note.md","base":"old\n","text":"new\n"}' $SAVE)" "200"
check "saved text is on disk" "$(cat "$BENTO_HOME/products/ed/docs/note.md")" "new"
check "stale save refused" "$(code -H "$JH" -d '{"path":"products/ed/docs/note.md","base":"old\n","text":"lost\n"}' $SAVE)" "409"
checkn "stale save changed nothing" "$(cat "$BENTO_HOME/products/ed/docs/note.md")" "lost"
check "save outside the workspace refused" "$(code -H "$JH" -d "{\"path\":\"../outside.md\",\"base\":\"secret\\n\",\"text\":\"x\"}" $SAVE)" "400"
check "outside file untouched" "$(cat "$T/outside.md")" "secret"
check "non-doc save refused" "$(code -H "$JH" -d '{"path":"bento.json","base":"","text":"x"}' $SAVE)" "400"
check "cross-site save refused" "$(code -H 'Origin: https://evil.example' -H "$JH" -d '{"path":"products/ed/docs/note.md","base":"new\n","text":"x"}' $SAVE)" "403"

# Project is expected on epics.
check "epic without a project is flagged" "$(cd /tmp && "$KB" add "Homeless epic")" "has no project"
checkn "scratchpad notes don't need a project" "$(cd /tmp && "$KB" add "Loose idea" --to scratchpad)" "has no project"

# Local history.
check "workspace has its own repo" "$(git -C "$BENTO_HOME" rev-parse --is-inside-work-tree)" "true"
check "workspace has no remote" "x$(git -C "$BENTO_HOME" remote)" "x"
[[ -z "$(git -C "$BENTO_HOME" remote)" ]] && echo "ok   nothing to push to" || { echo "FAIL remote"; fail=1; }
sleep 1
"$KB" add "Snapshot me" -p hist >/dev/null
SNAP=$(python3 - "$KB" <<'PYEOF'
import importlib.machinery,importlib.util,sys
loader=importlib.machinery.SourceFileLoader("kb",sys.argv[1]); spec=importlib.util.spec_from_loader("kb",loader); m=importlib.util.module_from_spec(spec); loader.exec_module(m)
print(m.snapshot_workspace(), m.snapshot_workspace())
PYEOF
)
check "snapshot commits once, then has nothing to do" "$SNAP" "True False"
check "history lists snapshots" "$("$KB" history)" "$(date +%Y-%m-%d)"
check "snapshot holds the board" "$(git -C "$BENTO_HOME" show HEAD:BOARD.md)" "Snapshot me"
checkn "snapshot skips the event log" "$(git -C "$BENTO_HOME" ls-files)" "EVENTS.log"
checkn "snapshot used no personal identity" "$(git -C "$BENTO_HOME" log -1 --format=%ae)" "gmail"

# Reports.
cd "$T/beta"
check "report needs a location" "$("$KB" report add "No Where" 2>&1)" "Say where it arrives"
check "unsafe link refused" "$("$KB" report add "Bad" --link 'javascript:alert(1)' 2>&1)" "must be an http"
check "report add" "$("$KB" report add "Daily Usage" -p beta --thread t-1 --schedule "Daily at 2:00")" "Tracking Daily Usage"
check "report list" "$("$KB" report list)" "codex://threads/t-1"
check "no copy yet" "$("$KB" report show "Daily Usage" 2>&1)" "No copy"
check "empty post refused" "$(printf '' | "$KB" report post "Daily Usage" 2>&1)" "empty"
check "report post" "$(printf '# Usage\n\nUp 4%%.\n' | "$KB" report post "Daily Usage")" "Posted Daily Usage"
check "report show" "$("$KB" report show daily-usage)" "Up 4%"
check "post stored under the project" "$(ls "$BENTO_HOME"/products/beta/reports/daily-usage)" ".md"
check "reports api" "$(curl -s http://127.0.0.1:47470/api/reports)" '"url": "codex://threads/t-1"'
check "report doc readable" "$(curl -s "http://127.0.0.1:47470/api/doc?path=$(ls "$BENTO_HOME"/products/beta/reports/daily-usage/*.md | sed "s#$BENTO_HOME/##")")" "Up 4%"
check "report rm keeps copies" "$("$KB" report rm "Daily Usage")" "were kept"
cd "$T"
kill $S1
exit $fail
