# Bento rules

Bento is the shared work queue and product documentation for {owner}, Claude and Codex. The workspace is at `{home}`. Board cards live in `BOARD.md`, and docs live in `products/<project>/`.

## Epics, not tickets

Every card is an **epic**: a meaningful group of work with one clear "done when". Don't make cards for single small tasks. List those inside the epic's plan instead. Notes on {owner}'s Scratchpad are the exception. They aren't work yet, agents never pick them up, and they become an epic when {owner} promotes one.

There are four kinds of epic, and each can have a plan:

| Kind | Covers | Plan lives at |
| --- | --- | --- |
| `implementation` | Building something | `products/<project>/plans/implementation-*.md` |
| `testing` | Verifying built epics as a group (`verifies: #12, #13`) | `products/<project>/plans/testing-*.md` |
| `release` | Shipping a set of epics, with its exit gate and rollback | `products/<project>/plans/release-*.md` |
| `writing` | A piece of writing, often timed to warm up an audience before a release | `products/<project>/plans/writing-*.md` |

A testing epic can't be picked up until the epics it verifies reach Review.

## Columns

| Column | Meaning | Who puts cards here |
| --- | --- | --- |
| Scratchpad | {owner}'s notes and ideas, one simple list, not attached to anything | {owner}, or an agent {owner} asked to save one |
| Milestones | Named dates that epics work toward; not shown on the kanban | {owner}, or an agent {owner} gave the date to |
| Backlog | Epics nobody has committed to | Anyone |
| Next | Committed work. **Top card goes first.** | {owner}, or a handoff {owner} asked for |
| Doing | Someone is working on it | Whoever claims it |
| Review | Finished, waiting for {owner} to check | Whoever did the work |
| Done | {owner} accepted it | {owner} only |

## What agents may do

- **"What's next?" is a read.** Run `kb next --as <you>` and answer from it. From a connected project it looks only at that project; add `--all-projects` for everything. Don't claim anything unless {owner} asked you to do the work.
- **Claim before you start.** Run `kb claim --as <you>`, or `kb claim 12 13 --as <you>` for a set of epics. If it refuses, don't work around it.
- **Work {owner} asks you for directly** can start from Backlog. Add it with `kb add` if it isn't on the board, then claim it with {owner}'s words: `kb claim 12 --as <you> --asked "<what {owner} said>"`. Quote them; don't paraphrase a yes out of a maybe. {owner} sees it in the Inbox and can stop it. Never use `--asked` for work you only noticed.
- **Write the testing plan before you build.** Right after claiming, run `kb test-plan <id>` and fill in the checks: what you'll verify, how, and what you expect. It goes in the epic's plan doc if it has one.
- **Run the tests before Review.** Run every check in the testing plan and record the results there. Then finish into Review, never Done: `kb review <id> --as <you> --tested "<what you ran and what happened>" --note "<what changed>" --link <where to check it>`. Review refuses without a testing plan and `--tested`. If something truly can't be tested yet, say why with `--untested "<why>"`; {owner} sees it flagged. The link is a URL (a preview, a staging page, a PR) or a doc in the workspace. {owner} opens it from the Inbox, so always give one.
- **Work for {owner}** (`for: {owner}`) needs a link too: `kb set <id> link <url or doc>`, so {owner} knows what to open.
- **Start of a session:** run `kb resume --as <you>` to see what you hold, what came back from {owner}, and what to do next.
- **Stuck?** Run `kb block <id> "<what you need>"` and tell {owner}. When there are clear choices, offer them: `kb block <id> "Which provider?" --option Stripe --option Paddle`. Don't guess past a real decision.
- **Decisions are {owner}'s.** Answers are recorded in `DECISIONS.md`; `kb why <id>` lists the ones behind an epic. Follow them. If {owner} decides something in conversation, record it: `kb decide "<what>" --implies 12,13 --as <you>`.
- **Don't move the bar quietly.** Once an epic is claimed, changing its done-when needs `--reason "<what the old one got wrong>"`, and {owner} sees the change in the Inbox.
- **New work you notice** goes in Backlog with `kb add`. Don't start it, and don't put it in Next.
- **Don't delete cards** unless {owner} asked you to.
- **Disagree with the order?** Say so to {owner}. Don't reorder Next yourself.
- If a card says `blocked: changes requested`, read the note and update the plan. {owner} clears it by approving.

Use your own name: `claude` or `codex`.

## Docs and pulling work

Product docs live in the workspace, not in project repos. `kb docs` lists them. Keep backlogs, roadmaps and plans current there. Don't copy a whole backlog onto the board. Pull only what is worth doing soon:

```
kb add "Saved searches" --source docs/BACKLOG.md#release-1 --release "Release 1" --done-when "..."
```

Every epic should have a project. `--project` defaults to the connected folder you are in; outside one, pass it yourself. `--source` points back to where the detail lives; `#anchor` is the heading text, lowercased, with spaces as dashes and punctuation removed.

## Handing epics to another agent

When {owner} has you hand work over, for example from Codex to Claude:

1. Write the plan: `kb plan implementation "Search" --epics 12 13`, then fill in the file it creates.
2. Hand it off: `kb handoff 12 13 --to claude --plan products/<project>/plans/implementation-search.md --as codex`.
3. The receiver runs `kb claim 12 13 --as claude`, reads the plan, and follows it.

{owner} can read, approve or request changes on any plan from the web board.

## Pushing work and hearing back

`kb push 12 13 --to codex` is the same as `kb handoff`, and the plan is optional. Never loop on `kb show` or `kb next` to check on work. After you push, end your turn. You hear back once, when every epic has reached Review, or right away if one gets blocked:

- **Codex:** `kb push` registers your session, and the Bento service resumes it with the news. To follow epics you didn't push, run `kb wake 12 13`.
- **Claude Code:** run `kb wait 12 13` as a background command. It sleeps until there's news, and your session wakes when it exits. Exit codes: 0 finished, 2 blocked, 3 timed out (with `--timeout`).

Pushing doesn't start an agent. Someone still has to ask the agent to pick the work up.

## Milestones and dependencies

Dates belong on milestones and releases, not on ordinary epics. A milestone is a named moment with one date, such as a launch or a publish date. It isn't work: agents never pick it up, and {owner} marks it reached. Epics feed a milestone through `needs`, and milestones in different projects can depend on each other.

```
kb add "Essay publishes" --kind milestone -p writing --target 2026-12-01 --needs 12,13
```

Each milestone or release can have a doc with its theme, acceptance criteria and release notes. Start one with `kb plan milestone "Essay publishes" --epics 14`, and keep its release notes current as epics finish. Set a short theme with `--theme` or `kb set 14 theme "..."`.

Only set a date {owner} gave you; don't invent one. `kb calendar` lists every milestone with its dependencies. A milestone is at risk if a dependency is blocked, a dependency is dated after it, or dependencies are open with 7 days or fewer left. It's late once the date passes.

## Daily reports

`kb report list` shows each recurring report, its project, and the thread it arrives in. `kb report show <name>` prints the latest copy posted to Bento. A report job should finish by posting its report: `kb report post <name> report.md`, or pipe it in. There's one copy per day. Don't treat the latest message in a report's thread as the report, because those threads also hold other conversation.

## Commands

```
kb                               the board across projects (-p my-app, --kind testing, --all, --json)
kb next --as codex               best card for you, changes nothing
kb inbox                         what's waiting on {owner} (--order blocked,review,plans to change it)
kb show 12                       one card in full
kb claim --as codex              take the best card (or: kb claim 12 13 --as codex)
kb claim 12 --as codex --asked "..."   take a Backlog card {owner} asked for, in their words
kb add "title" --kind testing --verifies 12,13 --done-when "..."
kb plan testing "Search" --epics 14
kb push 12 13 --to claude --plan <path> --as codex
kb wait 12 13                    sleep until they reach Review or get stuck (--until done, --timeout 600)
kb wake 12 13                    have this Codex session resumed when they finish
kb set 12 needs "#9"             change a field (leave the value empty to clear it)
kb add "title" --to scratchpad    save a note or idea
kb delete 12                     move a card to TRASH.md, only if {owner} asked (kb restore 12 undoes it)
kb note 12 "text" --as codex     add a dated note
kb block 12 "reason"             flag a card as stuck (kb unblock 12 clears it; --option A --option B offers choices)
kb resume --as codex             what you hold, what came back, what to do next
kb why 12                        the decisions behind a card
kb decide "text" --implies 12    record a decision {owner} made
kb health                        everything stuck, since when, and who's next
kb digest                        a short Markdown briefing of the board
kb test-plan 12                  start the epic's testing plan, before you build
kb review 12 --as codex --tested "what ran, what passed" --note "text" --link https://preview.example.com
kb move 12 next --top            move or release a card ({owner}'s call for Next and Done)
kb calendar                      milestones and their dependencies (-p my-app, --json)
kb docs                          product docs and plans (--long, --all-projects)
kb projects                      connected projects
kb archive                       move Done cards to ARCHIVE.md
kb open                          open the web board, starting it if needed
kb serve                         run the web board at http://127.0.0.1:4747
```

## Card format

Prefer the commands, since they lock the file. For a hand edit, a card looks like this:

```markdown
### #12 Short title
- for: any
- kind: implementation
- project: my-app
- release: Release 1
- source: products/my-app/docs/BACKLOG.md#release-1
- plan: products/my-app/plans/implementation-search.md
- link: https://preview.example.com/search
- needs: #9
- verifies: #7
- target: 2026-12-01
- blocked: waiting on an API key
- claimed: codex 2026-11-06
- done when: What has to be true for this to be finished.

Free-form notes go below the fields.
```

Every field is optional, but a card in Next should have `done when`. A new `### Title` with no number gets one automatically on the next write. Don't start a note line with `##` or `###`; those mark columns and cards.
