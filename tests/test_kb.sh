#!/bin/zsh
# Exercises kb against a throwaway workspace and throwaway repos, never the real ones.
KB="${0:A:h:h}/kb"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export BENTO_HOME="$T/home"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
check() { if [[ "$2" == *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1"; echo "     wanted: $3"; echo "     got: $2"; fail=1; fi; }
newid() { sed -E 's/Added ([A-Z]+[0-9]+).*/\1/'; }
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
# Most of this file isn't about testing before review, so it's off until that block.
notests() { python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); c["review"]={"require_tests": False}; json.dump(c, open(sys.argv[1],"w"))' "$BENTO_HOME/bento.json"; }
notests
check "connect with import" "$("$KB" connect "$T/alpha" --import-docs)" "Imported 3 docs"
check "connect from a plain folder" "$(cd "$T/beta" && "$KB" connect --name beta)" "Connected beta"
check "connect refuses the home folder" "$(HOME="$T/beta" "$KB" connect "$T/beta" 2>&1)" "too broad"
check "connect refuses the root folder" "$("$KB" connect / 2>&1)" "too broad"
check "imports default branch, not worktree" "$(cat "$BENTO_HOME/products/alpha/docs/BACKLOG.md")" "Alpha backlog"
check "no code imported" "$(ls -R "$BENTO_HOME/products/alpha")" "SOURCE.md"
checkn "no code imported 2" "$(ls -R "$BENTO_HOME/products/alpha")" "app.py"
[[ ! -e "$T/alpha/.bento" && -z "$(git -C "$T/alpha" status --porcelain)" ]] && echo "ok   connect adds nothing to the repo" || { echo "FAIL repo touched"; fail=1; }
check "projects lists both" "$("$KB" projects)" "beta"
check "worktree detected by remote" "$(cd "$T/alpha-wt" && "$KB" projects)" "* A    alpha"
check "plain folder detected by path" "$(cd "$T/beta" && "$KB" projects)" "* B    beta"
checkn "unconnected folder detected as nothing" "$(cd /tmp && "$KB" projects)" "*"

cd "$T/alpha-wt"
check "add defaults project from folder" "$("$KB" add 'F1 Build it' --to next --source docs/BACKLOG.md#release-1 --done-when works)" "(alpha)"
check "source resolved" "$("$KB" show A1)" "source: products/alpha/docs/BACKLOG.md#release-1"
check "bad source refused" "$("$KB" add x --source docs/NOPE.md 2>&1)" "No doc at"
check "doc outside workspace refused" "$("$KB" add x --source ../../../../etc/hosts.md 2>&1)" "No doc at"
"$KB" add "F2 Other" --to next --for codex >/dev/null
(cd "$T/beta" && "$KB" add "Beta epic" --to next >/dev/null)
"$KB" add "Test F1 and F2" --kind testing --verifies A1,A2 --to next >/dev/null
check "bad kind refused" "$("$KB" add x --kind nope 2>&1)" "Kind must be"

check "next scoped to this project" "$("$KB" next --as claude)" "in alpha"
check "next from beta sees beta" "$(cd "$T/beta" && "$KB" next --as claude)" "Beta epic"
check "next all projects" "$("$KB" next --as claude --all-projects)" "F1 Build it"
check "list across projects" "$("$KB")" "Beta epic"
checkn "list filtered to a project" "$("$KB" -p alpha)" "Beta epic"
check "list filtered by kind" "$("$KB" --kind testing)" "Test F1 and F2"
checkn "list filtered by kind 2" "$("$KB" --kind testing)" "F1 Build it"

check "testing waits for build" "$("$KB" claim A3 --as claude --also 2>&1)" "nothing to test until"
check "plan created" "$("$KB" plan implementation 'Free Beta!' --epics A1 A2)" "implementation-free-beta.md"
check "plan lists epics" "$(cat "$BENTO_HOME/products/alpha/plans/implementation-free-beta.md")" "- A1 F1 Build it"
check "plan linked to card" "$("$KB" show A2)" "plan: products/alpha/plans/implementation-free-beta.md"
check "duplicate plan refused" "$("$KB" plan implementation 'Free Beta!' 2>&1)" "already exists"
check "plan needs a project" "$(cd /tmp && "$KB" plan release x 2>&1)" "Which project"
check "docs lists plan" "$("$KB" docs)" "plans/implementation-free-beta.md"

P=products/alpha/plans/implementation-free-beta.md
check "handoff" "$("$KB" handoff A1 a2 --to claude --plan $P --as codex)" "Handed A1, A2 to claude"
check "handoff sets target" "$("$KB" show A2)" "for: claude"
check "handoff keeps order at top" "$("$KB" --json | python3 -c "import json,sys; d=json.load(sys.stdin); print([c['id'] for c in [x for x in d['columns'] if x['name']=='Next'][0]['cards']][:2])")" "['A1', 'A2']"
check "other agent can't take handed card" "$("$KB" claim A1 --as codex 2>&1)" "for claude"
check "claim a set" "$("$KB" claim A1 A2 --as claude)" "#A2 F2 Other"
check "claim shows plan" "$("$KB" show A1)" "claimed: claude"
check "testing still waits on review" "$("$KB" next --as codex)" "reach"
check "review" "$("$KB" review A1 --as claude --note done)" "in Review"
"$KB" review A2 --as claude >/dev/null
check "testing ready after review" "$("$KB" next --as codex)" "Test F1 and F2"
check "archive keeps ids" "$("$KB" move A1 done >/dev/null; "$KB" archive; "$KB" add after)" "Added A4"

# The scratchpad is ignored by agents.
"$KB" add "Call the plumber" --to scratchpad --for sam -p "" >/dev/null
checkn "scratchpad not offered to agents" "$("$KB" next --as codex --all-projects)" "plumber"

# Hand edits survive.
printf '\n## Parking\n\n### Handwritten card\n- for: sam\n\n```\n## not a column\n```\n' >> "$BENTO_HOME/BOARD.md"
"$KB" note B1 x >/dev/null
check "extra column and fence kept" "$(cat "$BENTO_HOME/BOARD.md")" "## not a column"
check "handwritten numbered" "$(cat "$BENTO_HOME/BOARD.md")" "### #N1 Handwritten card"

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
check "changes block the card" "$("$KB" show A6)" "blocked: changes requested: more detail"
check "approve" "$(code -H "$J" -d "{\"plan\":\"$P\",\"decision\":\"approve\"}" $U/api/review)" "200"
check "approve clears the block" "$("$KB" show A6)" "approved: sam"
checkn "approve clears the block 2" "$("$KB" show A6)" "blocked:"
check "stale edit refused" "$(code -H "$J" -d '{"id":"A6","title":"x","body":"","base_body":"old","base_title":"Plan card"}' $U/api/edit)" "409"
kill $SP

# Agent setup writes only marked blocks and is repeatable.
FAKE="$T/fakehome"; mkdir -p "$FAKE/.codex" "$FAKE/.claude"
printf '# Mine\n\nKeep this.\n' > "$FAKE/.codex/AGENTS.md"; printf 'model = "x"\n' > "$FAKE/.codex/config.toml"
HOME="$FAKE" "$KB" install-agents >/dev/null; HOME="$FAKE" "$KB" install-agents >/dev/null
check "existing instructions kept" "$(cat "$FAKE/.codex/AGENTS.md")" "Keep this."
[[ $(grep -c 'bento:start' "$FAKE/.codex/AGENTS.md") == 1 ]] && echo "ok   block not duplicated" || { echo "FAIL duplicated block"; fail=1; }
[[ $(grep -c 'writable_roots' "$FAKE/.codex/config.toml") == 1 ]] && echo "ok   codex root added once" || { echo "FAIL codex root"; fail=1; }
check "owner in block" "$(cat "$FAKE/.claude/CLAUDE.md")" "sam, Claude and Codex"
check "block knows open bento" "$(cat "$FAKE/.claude/CLAUDE.md")" 'says "open bento", run `kb open`'
check "block knows note for bento" "$(cat "$FAKE/.codex/AGENTS.md")" "--to scratchpad --as codex"
check "rules fill in owner" "$("$KB" rules)" "for sam, Claude and Codex"
ls -a "$BENTO_HOME" | grep -q '^\.kb-' && { echo "FAIL temp files left"; fail=1; } || echo "ok   no temp files left"

# Uninstalling undoes only what install added.
check "uninstall reports removal" "$(HOME="$FAKE" "$KB" uninstall-agents)" "Removed Bento instructions from ~/.codex/AGENTS.md"
check "own instructions survive uninstall" "$(cat "$FAKE/.codex/AGENTS.md")" "Keep this."
checkn "block gone from codex" "$(cat "$FAKE/.codex/AGENTS.md")" "bento:start"
[[ ! -e "$FAKE/.claude/CLAUDE.md" ]] && echo "ok   file holding only the block removed" || { echo "FAIL claude file left"; fail=1; }
check "own config survives uninstall" "$(cat "$FAKE/.codex/config.toml")" 'model = "x"'
checkn "codex root gone" "$(cat "$FAKE/.codex/config.toml")" "writable_roots"
check "uninstall repeats safely" "$(HOME="$FAKE" "$KB" uninstall-agents)" "No Bento instructions in ~/.codex/AGENTS.md"
check "workspace kept" "$(ls "$BENTO_HOME")" "BOARD.md"
printf '[sandbox_workspace_write]\nnetwork_access = true\nwritable_roots = ["/a", "%s"]\n' "$(cd "$BENTO_HOME" && pwd -P)" > "$FAKE/.codex/config.toml"
check "shared setting left to the user" "$(HOME="$FAKE" "$KB" uninstall-agents)" "yourself"
check "shared setting not edited" "$(cat "$FAKE/.codex/config.toml")" "network_access = true"

# Push and push back.
export BENTO_HOME="$T/notify"
"$KB" init "$BENTO_HOME" --owner sam >/dev/null
notests
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

# kb open starts the board when it isn't running, then just opens it.
OPENED=$(BROWSER=true "$KB" open --port 47479)
check "open starts the board" "$OPENED" "Started Bento in the background"
check "open opens the board" "$OPENED" "Opened http://127.0.0.1:47479"
check "board answers after open" "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:47479/api/board)" "200"
AGAIN=$(BROWSER=true "$KB" open --port 47479)
check "open reuses a running board" "$AGAIN" "Opened"
checkn "open doesn't start a second board" "$AGAIN" "Started"
check "open agrees with serve on a running board" "$(BROWSER=true "$KB" open --port 47470)" "Opened http://127.0.0.1:47470"
kill "$(print -r -- "$OPENED" | grep -oE 'pid [0-9]+' | cut -d' ' -f2)" 2>/dev/null
curl -sN --max-time 3 http://127.0.0.1:47470/api/stream > "$T/stream.txt" &
CURL=$!
sleep 0.5
"$KB" add "Pushed epic" -p x >/dev/null
check "push moves to Next" "$("$KB" push X1 --to codex --as sam)" "Handed X1 to codex"
start=$SECONDS
("$KB" wait X1 > "$T/wait.txt"; echo "code=$?" >> "$T/wait.txt") &
WAITER=$!
sleep 0.5
"$KB" claim X1 --as codex >/dev/null
"$KB" review X1 --as codex --note "shipped" >/dev/null
wait $WAITER
(( SECONDS - start < 3 )) && echo "ok   wait woke straight away" || { echo "FAIL wait was slow"; fail=1; }
check "wait returns the result" "$(cat "$T/wait.txt")" "shipped"
check "wait exits 0" "$(cat "$T/wait.txt")" "code=0"
wait $CURL
check "web board gets a live message" "$(cat "$T/stream.txt")" "data: change"
sleep 0.5
check "agent finishing notifies the owner" "$(cat "$SENT")" "X1 Pushed epic is ready for review"
[[ $(grep -c 'ready for review' "$SENT") == 1 ]] && echo "ok   two servers deliver once" || { echo "FAIL duplicate delivery"; cat "$SENT"; fail=1; }
"$KB" move X1 done --as sam >/dev/null; sleep 0.5
checkn "owner's own moves stay quiet" "$(cat "$SENT")" "is done"
"$KB" add "Stuck epic" -p x --to next >/dev/null
"$KB" block X2 "need a key"; sleep 0.5
check "blocked notifies" "$(cat "$SENT")" "X2 Stuck epic needs you: need a key"
"$KB" wait X2 >/dev/null; check "wait exits 2 when blocked" "$?" "2"
"$KB" unblock X2 >/dev/null
"$KB" wait X2 --timeout 1 >/dev/null; check "wait exits 3 on timeout" "$?" "3"
"$KB" archive >/dev/null
"$KB" wait X1 >/dev/null; check "wait sees archived as finished" "$?" "0"
"$KB" wait X99 >/dev/null 2>&1; check "wait refuses unknown card" "$?" "1"

# Waking a Codex session: once for the whole set, not for its own actions.
FAKEBIN="$T/bin"; mkdir -p "$FAKEBIN"; WOKE="$T/woke.txt"; : > "$WOKE"
printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$(pwd -P)" "$*" >> "%s"\n' "$WOKE" > "$FAKEBIN/codex"; chmod +x "$FAKEBIN/codex"
kill $S1 $S2; sleep 0.3
PATH="$FAKEBIN:$PATH" "$KB" serve --port 47470 --no-open >/dev/null 2>&1 &
S1=$!
sleep 1
"$KB" add "Set A" -p x >/dev/null; "$KB" add "Set B" -p x >/dev/null
cd "$T/beta"
check "codex push registers its session" "$(env -u CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID=thread-1 "$KB" push X3 X4 --to claude --as codex)" "will be resumed"
check "claude push suggests wait" "$(env -u CODEX_THREAD_ID CLAUDE_CODE_SESSION_ID=abc "$KB" add 'Set C' -p x >/dev/null; env -u CODEX_THREAD_ID CLAUDE_CODE_SESSION_ID=abc "$KB" push X5 --to codex --as claude)" "kb wait X5"
cd "$T"
"$KB" claim X3 --as claude --also >/dev/null; "$KB" review X3 --as claude >/dev/null; sleep 0.7
[[ ! -s "$WOKE" ]] && echo "ok   no wake until the whole set is finished" || { echo "FAIL woke early"; fail=1; }
"$KB" block X4 "need a call"; sleep 0.7
check "blocked wakes right away" "$(cat "$WOKE")" "X4 Set B is blocked: need a call"
check "wake targets the right session" "$(cat "$WOKE")" "resume thread-1"
check "wake runs in the session folder" "$(cat "$WOKE")" "$(cd "$T/beta" && pwd -P)|"
: > "$WOKE"; "$KB" unblock X4 >/dev/null; "$KB" claim X4 --as claude --also >/dev/null; "$KB" review X4 --as claude >/dev/null; sleep 0.7
check "finished set wakes the session" "$(cat "$WOKE")" "X3 Set A; X4 Set B finished"
[[ $(wc -l < "$WOKE" | tr -d ' ') == 1 ]] && echo "ok   wakes once" || { echo "FAIL multiple wakes"; cat "$WOKE"; fail=1; }
: > "$WOKE"; env -u CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID=thread-2 "$KB" add "Own" -p x >/dev/null; N=X6
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
T2=$("$KB" add "Dep test" -p cal --kind testing --verifies $DEP | newid)
REL=$("$KB" add "Ship it" -p cal --kind release --needs $T2 --target "$(date -v+30d +%F)" | newid)
check "dependency dated later is at risk" "$("$KB" calendar -p cal)" "at risk, 0 of 2 dependencies done  $DEP is dated after this"
check "dependencies are transitive" "$("$KB" calendar -p cal)" "$DEP Dep build: Milestones"
"$KB" set $REL target "$SOON" >/dev/null; "$KB" set $DEP target >/dev/null
check "open deps close to the date are at risk" "$("$KB" calendar -p cal)" "2 dependencies are open with 3 days left"
"$KB" set $REL target "$PAST" >/dev/null
check "past date is late" "$("$KB" calendar -p cal)" "late"
"$KB" set $REL target "$FAR" >/dev/null
check "far date with open deps is on track" "$("$KB" calendar -p cal)" "on track"
"$KB" block $DEP "waiting" >/dev/null
check "blocked dep is at risk" "$("$KB" calendar -p cal)" "$DEP is blocked"
"$KB" unblock $DEP >/dev/null; "$KB" set $REL target >/dev/null
check "undated release listed" "$("$KB" calendar -p cal)" "no date"
check "plain epics can't take a date" "$("$KB" add "Plain" -p cal --target "$FAR" 2>&1)" "Dates belong on milestones"
PLAIN=$("$KB" add "Plain epic" -p cal | newid)
check "plain epics can't be given a date" "$("$KB" set $PLAIN target "$FAR" 2>&1)" "Dates belong on milestones"
check "date api refuses plain epics" "$(code -H 'Content-Type: application/json' -d "{\"id\":\"$PLAIN\",\"field\":\"target\",\"value\":\"$FAR\"}" http://127.0.0.1:47470/api/set)" "400"
check "milestone lands in its column" "$("$KB" add "Launch day" -p cal --kind milestone)" "to Milestones"
checkn "milestones aren't offered as work" "$("$KB" next --as codex --all-projects)" "Launch day"
"$KB" move $REL done >/dev/null; check "finished release is reached" "$("$KB" calendar -p cal)" "reached"; "$KB" move $REL backlog >/dev/null
"$KB" set $REL theme "Pay without friction" >/dev/null
check "theme shows on the calendar" "$("$KB" calendar -p cal)" "Theme: Pay without friction"
check "milestone doc api" "$(curl -s -H 'Content-Type: application/json' -d "{\"id\":\"$REL\"}" http://127.0.0.1:47470/api/milestone-doc)" "plans/release-ship-it.md"
check "doc linked to the milestone" "$("$KB" calendar -p cal)" "Doc: products/cal/plans/release-ship-it.md"
check "second request reuses the doc" "$(curl -s -H 'Content-Type: application/json' -d "{\"id\":\"$REL\"}" http://127.0.0.1:47470/api/milestone-doc)" "plans/release-ship-it.md"
check "milestone doc lists its dependencies" "$(cat "$BENTO_HOME/products/cal/plans/release-ship-it.md")" "Dep test"
checkn "milestone doc doesn't list itself" "$(cat "$BENTO_HOME/products/cal/plans/release-ship-it.md")" "- $REL "
check "release doc has its sections" "$(cat "$BENTO_HOME/products/cal/plans/release-ship-it.md")" "## Release notes"
check "milestone doc has acceptance criteria" "$("$KB" plan milestone "Launch day" -p cal; cat "$BENTO_HOME/products/cal/plans/milestone-launch-day.md")" "## Acceptance criteria"
check "plain epics don't get a milestone doc" "$(code -H 'Content-Type: application/json' -d "{\"id\":\"$PLAIN\"}" http://127.0.0.1:47470/api/milestone-doc)" "400"
check "bad date refused by set" "$("$KB" set $REL target tomorrow 2>&1)" "Dates look like"
check "target api" "$(code -H 'Content-Type: application/json' -d "{\"id\":\"$REL\",\"field\":\"target\",\"value\":\"$FAR\"}" http://127.0.0.1:47470/api/set)" "200"
check "target api refuses other fields" "$(code -H 'Content-Type: application/json' -d "{\"id\":\"$REL\",\"field\":\"for\",\"value\":\"x\"}" http://127.0.0.1:47470/api/set)" "400"
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
ID0=$("$KB" add "Base epic" -p del | newid)
ID1=$("$KB" add "Waits on base" -p del --needs $ID0 | newid)
env -u CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID=thread-9 "$KB" wake $ID0 $ID1 >/dev/null
: > "$WOKE"
check "delete" "$("$KB" delete $ID0)" "kb restore $ID0"
check "deleted card leaves the board" "$("$KB" show $ID0 2>&1)" "No card"
checkn "dependents are cleared" "$("$KB" show $ID1)" "needs:"
check "trash keeps it" "$(cat "$BENTO_HOME/TRASH.md")" "Base epic"
sleep 0.5
[[ ! -s "$WOKE" ]] && echo "ok   deleting doesn't falsely wake a session" || { echo "FAIL false wake"; cat "$WOKE"; fail=1; }
check "wake list drops the card" "$(cat "$BENTO_HOME/.notify.wake.json")" "$ID1"
checkn "wake list drops the card 2" "$(python3 -c "import json;print([w['ids'] for w in json.load(open('$BENTO_HOME/.notify.wake.json'))])")" "'$ID0'"
ID2=$("$KB" add "After delete" -p del | newid)
(( ${ID2//[A-Z]/} > ${ID1//[A-Z]/} )) && echo "ok   deleted ids aren't reused" || { echo "FAIL id reuse $ID2"; fail=1; }
check "restore" "$("$KB" restore $ID0)" "to Backlog"
check "restored card is back" "$("$KB" show $ID0)" "Base epic"
checkn "restored card left the trash" "$(cat "$BENTO_HOME/TRASH.md")" "Base epic"
check "restore unknown refused" "$("$KB" restore DE9999 2>&1)" "No card DE9999"
check "delete unknown refused" "$("$KB" delete DE9999 2>&1)" "No card"
check "delete api" "$(code -H 'Content-Type: application/json' -d "{\"id\":\"$ID2\"}" http://127.0.0.1:47470/api/delete)" "200"
check "delete api needs json" "$(code -d "{\"id\":\"$ID0\"}" http://127.0.0.1:47470/api/delete)" "403"
check "delete api refuses other sites" "$(code -H 'Origin: https://evil.example' -H 'Content-Type: application/json' -d "{\"id\":\"$ID0\"}" http://127.0.0.1:47470/api/delete)" "403"
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

# Inbox: what's waiting on the owner, in an order the owner picks.
J='Content-Type: application/json'; U=http://127.0.0.1:47470
sections() { "$KB" inbox -p inb --json | python3 -c "import json,sys; print(','.join(dict.fromkeys(i['section'] for i in json.load(sys.stdin)['items'])))"; }
section_of() { "$KB" inbox -p inb --json | python3 -c "import json,sys; print([i['section'] for i in json.load(sys.stdin)['items'] if '$1' in i['ids']])"; }
IB=$("$KB" add "Stuck one" -p inb --to next --done-when x | newid); "$KB" block $IB "which database?" >/dev/null
IN=$("$KB" add "No finish line" -p inb --to next | newid)
IR=$("$KB" add "Built it" -p inb --to next --done-when x | newid)
"$KB" claim $IR --as codex --also >/dev/null; "$KB" review $IR --as codex >/dev/null
IP=$("$KB" add "Planned" -p inb --done-when x | newid); "$KB" plan implementation "Inbox plan" -p inb --epics $IP >/dev/null
"$KB" add "Loose idea" --to scratchpad -p inb >/dev/null
check "inbox lists what's waiting" "$("$KB" inbox -p inb)" "which database?"
check "inbox default order" "$(sections)" "blocked,plans,review,done-when,scratchpad"
check "inbox order can be set" "$("$KB" inbox --order review,blocked)" "Inbox order: review, blocked"
check "inbox follows the order" "$(sections)" "review,blocked"
checkn "inbox hides sections left out" "$("$KB" inbox -p inb)" "Loose idea"
check "unknown inbox section refused" "$("$KB" inbox --order review,nope 2>&1)" "Unknown inbox section: nope"
"$KB" set $IN for sam >/dev/null; "$KB" inbox --order yours,done-when >/dev/null
check "a card shows in the higher section" "$(section_of $IN)" "['yours']"
"$KB" inbox --order done-when,yours >/dev/null
check "and moves when the order changes" "$(section_of $IN)" "['done-when']"
check "inbox order resets" "$("$KB" inbox --reset)" "blocked, asked, plans, review, changed, done-when, quiet, yours, milestones, scratchpad"
check "board data has the inbox" "$(curl -s $U/api/board)" '"inbox_order"'
check "answer clears a block" "$(code -H "$J" -d "{\"id\":\"$IB\",\"text\":\"Postgres\"}" $U/api/answer)" "200"
check "answer is noted as a decision" "$("$KB" show $IB)" "answered (D1): Postgres"
checkn "answer unblocks" "$("$KB" show $IB)" "blocked:"
check "answering an unblocked card refused" "$(code -H "$J" -d "{\"id\":\"$IB\"}" $U/api/answer)" "400"
check "send back needs a comment" "$(code -H "$J" -d "{\"id\":\"$IR\"}" $U/api/send-back)" "400"
check "send back" "$(code -H "$J" -d "{\"id\":\"$IR\",\"comment\":\"needs a test\"}" $U/api/send-back)" "200"
check "sent back to Doing with the note" "$("$KB" show $IR --json)" '"column": "Doing"'
check "send back note" "$("$KB" show $IR)" "sent back (other): needs a test"
check "only Review can be sent back" "$(code -H "$J" -d "{\"id\":\"$IR\",\"comment\":\"x\"}" $U/api/send-back)" "400"
check "done-when needs text" "$(code -H "$J" -d "{\"id\":\"$IN\",\"field\":\"done when\",\"value\":\" \"}" $U/api/set)" "400"
check "done-when api" "$(code -H "$J" -d "{\"id\":\"$IN\",\"field\":\"done when\",\"value\":\"it ships\"}" $U/api/set)" "200"
check "done-when saved" "$("$KB" show $IN)" "done when: it ships"
code -H "$J" -d "{\"plan\":\"products/inb/plans/implementation-inbox-plan.md\",\"decision\":\"changes\",\"comment\":\"more\"}" $U/api/review >/dev/null
checkn "changes requested waits on the agent, not the owner" "$("$KB" inbox -p inb)" "Planned"
check "inbox order api" "$(code -H "$J" -d '{"order":["scratchpad","review"]}' $U/api/inbox-order)" "200"
check "inbox order api saved" "$(cat "$BENTO_HOME/bento.json")" '"scratchpad"'
check "inbox order api refuses junk" "$(code -H "$J" -d '{"order":"blocked"}' $U/api/inbox-order)" "400"
"$KB" inbox --reset >/dev/null
OLD=$("$KB" add "Past launch" -p inb --kind milestone --target "$(date -v-3d +%F)" | newid)
check "milestones past their date are in the inbox" "$(section_of $OLD)" "['milestones']"
check "past milestone says when it was due" "$("$KB" inbox -p inb)" "Was due"
"$KB" set $OLD target "$(date -v+30d +%F)" >/dev/null
check "future milestones stay out" "$(section_of $OLD)" "[]"
IL=$("$KB" add "Linked work" -p inb --to next --done-when x | newid); "$KB" claim $IL --as codex --also >/dev/null
"$KB" note $IL "Preview at https://preview.example.com/a." --as codex >/dev/null
check "review takes a link" "$("$KB" review $IL --as codex --link https://staging.example.com/b)" "in Review"
check "link saved on the card" "$("$KB" show $IL)" "link: https://staging.example.com/b"
LINKS=$("$KB" inbox -p inb --json | python3 -c "import json,sys; print([i['links'] for i in json.load(sys.stdin)['items'] if i['id']=='$IL'][0])")
check "inbox item carries the link first" "$LINKS" "['https://staging.example.com/b', 'https://preview.example.com/a']"
"$KB" add "Check the copy" -p inb --for sam --source products/inb/plans/implementation-inbox-plan.md >/dev/null
check "inbox item carries the source doc" "$("$KB" inbox -p inb --json)" '"source": "products/inb/plans/implementation-inbox-plan.md"'
check "rules ask agents for a link" "$("$KB" rules)" "--link <where to check it>"

# Decisions, changing the bar, health, briefings and shipping.
P1=$("$KB" add "Payments" -p pm --to next --done-when "Card payments work" | newid)
P2=$("$KB" add "Receipts" -p pm --to next --done-when "Receipts send" | newid)
P3=$("$KB" add "Refunds" -p pm | newid)
"$KB" claim $P1 --as claude --also >/dev/null
check "block with options" "$("$KB" block $P1 "Which provider?" --option Stripe --option "Paddle | maybe")" "picks from: Stripe; Paddle / maybe"
OPTS=$("$KB" inbox -p pm --json | python3 -c "import json,sys; print([i['options'] for i in json.load(sys.stdin)['items'] if i['id']=='$P1'])")
check "inbox carries the options" "$OPTS" "[['Stripe', 'Paddle / maybe']]"
check "answer by option number" "$("$KB" answer $P1 1 --implies $P2)" "recorded D2"
check "answer clears options" "$("$KB" show $P1 | grep -c options:)" "0"
check "decision noted on the card it implies" "$("$KB" show $P2)" "D2 applies here (from $P1): Stripe"
check "why lists the decision" "$("$KB" why $P2)" "D2"
check "why keeps the question" "$("$KB" why $P1)" "Asked: Which provider?"
check "decisions file is markdown" "$(cat "$BENTO_HOME/DECISIONS.md")" "### D2 Stripe"
"$KB" block $P1 "Refund window?" >/dev/null
check "card numbers in an answer count as implied" "$(code -H "$J" -d "{\"id\":\"$P1\",\"text\":\"30 days, also for $P3\"}" $U/api/answer)" "200"
check "implied by mention" "$("$KB" why $P3)" "30 days"
check "decide supersedes" "$("$KB" decide "Use Paddle" --implies $P1 --supersedes d2)" "Recorded D4"
check "superseded decision is marked" "$("$KB" why $P2)" "Replaced by D4"
check "cards of the old decision hear about it" "$("$KB" show $P2)" "D4 replaced D2: Use Paddle"
check "a decision can't be replaced twice" "$("$KB" decide "x" --supersedes D2 2>&1)" "already replaced by D4"
check "unknown decision refused" "$("$KB" decide "x" --supersedes D99 2>&1)" "No decision D99"
check "card json carries decisions" "$("$KB" show $P2 --json)" '"superseded_by": "D4"'
check "claimed done-when needs a reason" "$("$KB" set $P1 "done when" Cards work --as claude 2>&1)" "needs --reason"
check "unclaimed done-when changes freely" "$("$KB" set $P2 "done when" Receipts email --as claude)" "Updated"
"$KB" set $P1 "done when" "Cards work in test mode" --as claude --reason "live keys later" >/dev/null
check "change is noted with its reason" "$("$KB" show $P1)" "changed the done-when: live keys later. Was: Card payments work"
check "agent's change is in the inbox" "$("$KB" inbox -p pm)" "claude changed it. Was: Card payments work"
check "the change is logged" "$(tail -3 "$BENTO_HOME/EVENTS.log")" '"bar changed"'
check "recorded fields can't be set by hand" "$("$KB" set $P1 "done when changed" x 2>&1)" "kb bar"
check "undo puts the old done-when back" "$(code -H "$J" -d "{\"id\":\"$P1\",\"decision\":\"undo\"}" $U/api/bar)" "200"
check "old done-when is back" "$("$KB" show $P1)" "done when: Card payments work"
checkn "change cleared" "$("$KB" show $P1)" "done when changed"
"$KB" set $P1 "done when" "Cards work in test mode" --as claude --reason "again" >/dev/null
check "keep the new done-when" "$("$KB" bar $P1 keep)" "kept the new one"
check "kept" "$("$KB" show $P1)" "done when: Cards work in test mode"
check "nothing to settle" "$("$KB" bar $P1 keep 2>&1)" "hasn't been changed"
check "owner change needs a reason too" "$("$KB" set $P1 "done when" "x y" --as sam 2>&1)" "needs --reason"
"$KB" set $P1 "done when" "Cards work" --as sam --reason "simpler" >/dev/null
checkn "owner's own change stays out of the inbox" "$("$KB" inbox -p pm)" "changed it"
"$KB" review $P1 --as claude --link https://pay.example.test >/dev/null
check "send back needs a known reason" "$("$KB" send-back $P1 "no" --reason vibes 2>&1)" "invalid choice"
check "send back with a reason" "$("$KB" send-back $P1 "Receipt email missing" --reason missing)" "back to Doing"
check "reason noted" "$("$KB" show $P1)" "sent back (something's missing): Receipt email missing"
check "sent back is logged" "$(tail -2 "$BENTO_HOME/EVENTS.log")" '"reason": "missing"'
check "resume shows what you hold" "$("$KB" resume --as claude -p pm)" "You hold:"
check "resume shows what came back" "$("$KB" resume --as claude -p pm)" "sent back (something's missing)"
check "resume shows decisions" "$("$KB" resume --as claude -p pm)" "D4"
check "resume says what to do" "$("$KB" resume --as claude -p pm)" "Next step: Read what came back on $P1"
check "resume needs a name" "$("$KB" resume 2>&1)" "Say who you are"
"$KB" note $P1 "Fixed the receipt email." --as claude >/dev/null
check "a reply clears what came back" "$("$KB" resume --as claude -p pm)" "Next step: Carry on with $P1"
"$KB" set $P1 claimed "claude 2026-01-02" >/dev/null; sed -i '' "s/^- $(date +%F) /- 2026-01-02 /" "$BENTO_HOME/BOARD.md"
check "quiet work is in the inbox" "$("$KB" inbox -p pm)" "No update from claude since 2026-01-02"
check "health finds quiet work" "$("$KB" health -p pm)" "No update since 2026-01-02"
"$KB" health -p pm >/dev/null; check "health exits 1 when stuck" "$?" "1"
check "health names who takes the next step" "$("$KB" health -p pm --json)" '"who": "claude"'
check "health api" "$(curl -s $U/api/health)" '"problem"'
"$KB" report add "Nightly" -p pm --link https://r.example.test --schedule "Daily at 2:00" >/dev/null
check "health finds a silent report" "$("$KB" health -p pm)" "No copy posted yet"
printf 'ok\n' | "$KB" report post Nightly >/dev/null
checkn "a fresh report is fine" "$("$KB" health -p pm)" "Nightly"
M1=$("$KB" add "Beta" -p pm --kind milestone --target 2026-11-01 --needs $P1,$P2 | newid)
check "late milestone in health" "$("$KB" health -p pm)" "Late: The date has passed, since"
check "ship refuses with nowhere to go" "$("$KB" ship $M1 2>&1)" "are not finished. Say where they go"
M2=$("$KB" add "GA" -p pm --kind milestone --target 2026-12-15 | newid)
check "ship moves unfinished epics to the next milestone" "$("$KB" ship $M1)" "Moved $P1, $P2 to $M2 GA"
check "next milestone needs them" "$("$KB" show $M2)" "needs: $P1, $P2"
check "the epic says where it went" "$("$KB" show $P2)" "moved from $M1 to $M2"
check "shipped milestone is Done" "$("$KB" show $M1)" "[Done]"
check "can't ship twice" "$("$KB" ship $M1 2>&1)" "already shipped"
check "only milestones ship" "$("$KB" ship $P1 2>&1)" "isn't a milestone"
M3=$("$KB" add "Later" -p pm --kind milestone --target 2027-01-01 --needs $P3 | newid)
check "ship can keep unfinished epics" "$("$KB" ship $M3 --keep)" "Shipped without $P3"
"$KB" add "GA 2" -p pm --kind milestone --target 2027-02-01 >/dev/null
check "ship api" "$(code -H "$J" -d "{\"id\":\"$M2\"}" $U/api/ship)" "200"
"$KB" note $P3 "key is sk-abcdefghijklmnop1234 and token=hunter2" >/dev/null
DIG=$("$KB" digest -p pm)
check "digest has headings" "$DIG" "## In progress"
check "digest lists decisions" "$DIG" "## Recent decisions"
check "digest counts send-backs" "$DIG" "something's missing: 1"
checkn "digest redacts keys" "$DIG" "sk-abcdefghijklmnop1234"
check "digest api" "$(curl -s $U/api/digest)" "# Bento briefing"
"$KB" digest -p pm --out "$T/brief.md" >/dev/null
check "digest writes a file" "$(cat "$T/brief.md")" "# Bento briefing for pm"
check "watch needs a file" "$("$KB" digest --watch 2>&1)" "needs --out"
check "redact keeps the label" "$(python3 -c "import importlib.machinery as m; k=m.SourceFileLoader('kb','$KB').load_module(); print(k.redact('password: abc123 and ghp_abcdefghijklmnopqrstuvwxyz'))")" "password: [redacted] and [redacted]"
python3 - "$BENTO_HOME/bento.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])); c["inbox"] = ["review", "blocked"]; c.pop("inbox_seen", None); json.dump(c, open(sys.argv[1], "w"))
PY
check "new sections join an old saved order" "$("$KB" inbox --json | python3 -c "import json,sys; print(json.load(sys.stdin)['order'])")" "['review', 'changed', 'quiet', 'blocked', 'asked']"
"$KB" inbox --reset >/dev/null

# Testing before review.
python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); c.pop("review"); json.dump(c, open(sys.argv[1],"w"))' "$BENTO_HOME/bento.json"
T1=$("$KB" add "Tested work" -p qa --to next --done-when "export works" | newid)
T2=$("$KB" add "Planned work" -p qa --to next --done-when "import works" | newid)
check "claim asks for a testing plan" "$("$KB" claim $T1 --as codex --also)" "kb test-plan $T1"
check "resume shows the missing plan" "$("$KB" resume --as codex -p qa)" "Testing plan: none yet"
check "review refused with no testing plan" "$("$KB" review $T1 --as codex 2>&1)" "has no testing plan"
check "test-plan starts a doc" "$("$KB" test-plan $T1)" "tests-tested-work.md"
check "card points at it" "$("$KB" show $T1)" "test plan: products/qa/plans/tests-tested-work.md"
check "an empty testing plan doesn't count" "$("$KB" review $T1 --as codex 2>&1)" "has no testing plan"
printf '| Export a board | kb export | a file | |\n' >> "$BENTO_HOME/products/qa/plans/tests-tested-work.md"
check "review wants a test report" "$("$KB" review $T1 --as codex 2>&1)" "Run the checks in products/qa/plans/tests-tested-work.md first"
check "both flags refused" "$("$KB" review $T1 --as codex --tested a --untested b 2>&1)" "not both"
check "review with a test report" "$("$KB" review $T1 --as codex --tested "ran the export check, it passed")" "in Review"
check "report noted" "$("$KB" show $T1)" "codex: tested: ran the export check, it passed"
check "inbox shows the report" "$("$KB" inbox)" "Tested: ran the export check, it passed"
check "inbox json carries the plan" "$("$KB" inbox --json | python3 -c "import json,sys; print([i['tested'] for i in json.load(sys.stdin)['items'] if i['id']=='$T1'][0])")" "'plan': 'products/qa/plans/tests-tested-work.md'"
"$KB" claim $T2 --as codex --also >/dev/null
"$KB" plan implementation "Import" -p qa --epics $T2 >/dev/null
check "implementation plans have a testing section" "$(cat "$BENTO_HOME/products/qa/plans/implementation-import.md")" "## Testing plan"
check "test-plan uses the plan doc" "$("$KB" test-plan $T2)" "implementation-import.md"
python3 - "$BENTO_HOME/products/qa/plans/implementation-import.md" <<'PY'
import sys; p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("| --- | --- | --- | --- |\n", "| --- | --- | --- | --- |\n| Import a sample | kb import | same cards | |\n", 1))
PY
check "a filled plan section counts" "$("$KB" test-plan $T2 2>&1)" "already has a testing plan in products/qa/plans/implementation-import.md"
check "untested is allowed but said out loud" "$("$KB" review $T2 --as codex --untested "no sample board yet")" "in Review"
check "inbox flags untested work" "$("$KB" inbox)" "NOT TESTED: no sample board yet"
T3=$("$KB" add "Owner's own" -p qa --to doing | newid)
check "the owner can review without tests" "$("$KB" review $T3 --as sam)" "in Review"
T4=$("$KB" add "No home" --to next | newid)
check "test-plan needs a project" "$("$KB" test-plan $T4 2>&1)" "has no project"

# Work the owner asks for directly.
A1=$("$KB" add "Site directions" -p qa --done-when "three directions to compare" | newid)
check "backlog claim says how" "$("$KB" claim $A1 --as codex --also 2>&1)" "kb claim $A1 --as codex --asked"
check "asked needs words" "$("$KB" claim $A1 --as codex --also --asked " " 2>&1)" "Quote what sam asked for"
check "asked needs a card" "$("$KB" claim --as codex --also --asked "go" 2>&1)" "Name the card"
check "claim from backlog on the owner's word" "$("$KB" claim $A1 --as codex --also --asked "build the site directions")" "Claimed by codex"
check "words noted" "$("$KB" show $A1)" "codex: claimed from Backlog on sam's word: \"build the site directions\""
check "card is in Doing" "$("$KB" show $A1)" "[Doing]"
check "inbox shows it" "$("$KB" inbox)" "codex says you asked: \"build the site directions\""
check "confirm" "$("$KB" confirm $A1)" "confirmed"
checkn "confirmed leaves the inbox" "$("$KB" inbox)" "says you asked"
check "confirm twice refused" "$("$KB" confirm $A1 2>&1)" "wasn't claimed on your word"
A2=$("$KB" add "Unasked" -p qa | newid)
"$KB" claim $A2 --as codex --also --asked "do it" >/dev/null
check "stop via api" "$(code -H "$J" -d "{\"id\":\"$A2\",\"decision\":\"stop\"}" $U/api/confirm)" "200"
check "stopped goes back to Backlog" "$("$KB" show $A2)" "[Backlog]"
check "stopped is unclaimed" "$("$KB" show $A2 | grep -c claimed:)" "0"
check "scratchpad still can't be claimed" "$("$KB" claim $("$KB" add "idea" --to scratchpad | newid) --as codex --also --asked "x" 2>&1)" "not Next"

# Project numbers, and moving an old board onto them.
SAVED_HOME="$BENTO_HOME"; export BENTO_HOME="$T/legacy"; mkdir -p "$BENTO_HOME/products/web/plans"
cat > "$BENTO_HOME/BOARD.md" <<'EOF'
# Board

## Next

### #3 Pay page
- for: any
- project: web
- needs: #1

Waits on #1, like owner/repo#3,#1 on GitHub.

### #1 Login
- for: any
- project: web

### #2 Write the post
- for: any
- project: words

## Doing

### #5 Mint first
- for: any
- project: mint

### #6 Mint Labs
- for: any
- project: mint-labs

### #7 Delta
- for: any
- project: delta
EOF
printf '# Archive\n\n### #4 Old web thing\n- project: web\n' > "$BENTO_HOME/ARCHIVE.md"
printf '# Decisions\n\n### D1 Use Stripe\n- card: #3\n- implies: #1\n' > "$BENTO_HOME/DECISIONS.md"
printf '{"id": 3, "type": "moved", "to": "Next"}\n' > "$BENTO_HOME/EVENTS.log"
printf '# Plan\n\n- #3 Pay page\n- #1 Login\n' > "$BENTO_HOME/products/web/plans/implementation-pay.md"
printf '{"owner": "sam"}\n' > "$BENTO_HOME/bento.json"
LIST=$("$KB" --all)
check "old board moves to project numbers" "$LIST" "W1 Login"
check "numbered in old order within a project" "$LIST" "W2 Pay page"
check "archived cards hold their numbers" "$(cat "$BENTO_HOME/ARCHIVE.md")" "### #W3 Old web thing"
check "references follow" "$("$KB" show W2)" "needs: W1"
check "mentions follow" "$("$KB" show W2)" "Waits on W1"
check "GitHub issue lists are left alone" "$("$KB" show W2)" "owner/repo#3,#1"
check "decisions follow" "$(cat "$BENTO_HOME/DECISIONS.md")" "card: W2"
check "why still finds them" "$("$KB" why W1)" "Use Stripe"
check "events follow" "$(cat "$BENTO_HOME/EVENTS.log")" '"id": "W2"'
check "plan lists follow" "$(cat "$BENTO_HOME/products/web/plans/implementation-pay.md")" "- W1 Login"
check "old numbers still work" "$("$KB" show 3)" "Pay page"
check "old numbers with a hash work" "$("$KB" show '#2')" "Write the post"
check "lowercase works" "$("$KB" show w1)" "Login"
check "a name and its initials don't clash" "$("$KB" --all)" "ML1 Mint Labs"
check "D is left for decisions" "$("$KB" --all)" "DE1 Delta"
check "keys are kept" "$(cat "$BENTO_HOME/bento.json")" '"mint-labs": "ML"'
check "new cards take the next number" "$("$KB" add "Signup" -p web)" "Added W4"
check "unknown numbers refused" "$("$KB" show W99 2>&1)" "No card W99"
check "plain numbers need their letters" "$("$KB" show 99 2>&1)" "like B12"
check "moving project renumbers" "$("$KB" set W4 project words)" "It's WO2 now"
check "moved card keeps its old number as an alias" "$("$KB" show W4)" "Signup"
check "taken numbers aren't reused" "$("$KB" add "Next one" -p web)" "Added W5"
check "no project numbers with N" "$("$KB" add "Loose" --to scratchpad)" "Added N1"
export BENTO_HOME="$SAVED_HOME"

# Every command is in the docs.
for c in $("$KB" --help | sed -n '/^commands:/,$p' | grep -oE '^    [a-z-]+' | tr -d ' '); do
  grep -q "kb $c" "${KB:h}/website/docs/index.html" || { echo "FAIL docs miss kb $c"; fail=1; }
done
echo "ok   every command is in the docs"

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
