# bento

A tidy little box for what's next.

## Why this exists

I build several products at once with Claude Code and Codex. The tools for keeping that work straight didn't fit, so I built this.

- **Trackers are too much.** Linear is built for teams. A person and a few agents need a queue everyone can read, not a system to administer.
- **Agents don't share a queue.** A Claude session can't see what a Codex session picked up. Someone has to keep the order in their head, and that someone was me.
- **Handoffs have no home.** I often iterate in Codex, then hand a set of epics to Claude with an implementation doc. That handoff shouldn't depend on me copying text between windows.
- **Checking on agents is a chore.** Work finishes while I'm elsewhere, and nobody tells the session that was waiting. A session should hear back when the work is done, without polling.
- **Product docs drift.** Backlogs and release plans live in each repo, with a copy in every worktree and branch. One of my backlogs still listed shipped work as unmerged.
- **My own tracking was on paper.** Sticky notes don't show up next to the work, and agents can't read them.
- **Release dates don't line up.** I often time writing to warm up an audience before a product release. Working backward takes apps and writing on one calendar, with dependencies you can see.

## What it is

Bento is a kanban board and product-doc home that you and your coding agents can all read and write. It's plain Markdown on your own machine, with one small script and a web board. No accounts, servers or dependencies beyond Python 3.9+ and git.

- **One view across projects**, filterable down to one.
- **Epics, not tickets.** Each card is a meaningful group of work with a clear "done when".
- **Implementation, testing, release and writing plans**, pulled from your backlogs and roadmaps.
- **Agent handoffs.** Iterate with one agent, then hand epics and a plan to another.
- **Safe claiming**, so two agents can't take the same card.
- **Delivery view:** what to take up next, what each item still needs from you, and what is ready to verify.
- **Calendar view:** milestones across projects, and how the work feeding each one stands.
- **Edit docs your way:** write on the board itself, or start a Codex or Claude Code thread on any doc.
- **Scratchpad:** loose notes and ideas, any of which can become an epic.

## Setup

```bash
git clone https://github.com/ckoglmeier/bento.git ~/bento
ln -s ~/bento/kb ~/.local/bin/kb
kb init ~/bento-data --owner yourname
kb install-agents
```

The tool and your data stay separate. This repo holds only code. Your board, docs and plans live in the workspace folder on your own machine. Bento keeps local snapshots of that folder in its own git repo, about once a minute while it's running, and it never pushes them anywhere. `kb history` lists them.

`kb install-agents` adds a short marked section to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`, and lets Codex's sandbox write to the workspace.

## Connect your projects

```bash
kb connect ~/code/my-app --import-docs
```

This registers the project in your workspace and adds nothing to its repo. Bento recognizes the project by its git remote, so every clone and worktree is connected automatically. `--import-docs` copies Markdown from `docs/`, plus root files like `BACKLOG.md` and `ROADMAP.md`, from the default branch into `products/my-app/`.

Imported docs are a copy. Decide which version is the real one: either keep editing in the workspace and leave a pointer in the repo, or re-run `kb import` to refresh.

## Use it

```bash
kb serve
```

Switch between Delivery, Calendar, Scratchpad and Board, filter by project, read docs, pull items from a doc onto the board, and approve plans.

Ask an agent "what's next?" from any connected project and it answers from the board. The rules agents follow are in [AGENTS.md](AGENTS.md), and `kb rules` prints them. `kb --help` lists every command.

## Track recurring reports

```bash
kb report add "App daily usage" --thread <codex-thread-id> -p my-app --schedule "Daily at 2:00"
```

The Reports panel on the board links to each report's thread, filtered by project. A report job can also post a dated copy with `kb report post "App daily usage" report.md`, which keeps its history in `products/my-app/reports/` where people and agents can read it.

## Hear back without polling

```bash
kb service install
```

This keeps Bento running in the background on macOS, and it starts at login. An agent that pushes work hears back once when the whole set reaches Review, or right away if an epic gets blocked:

- **Codex:** the service runs `codex exec resume` on the session that pushed.
- **Claude Code:** the session runs `kb wait 12 13` as a background command, which sleeps on a kernel file event and wakes the session when it exits.

The web board updates live the same way. On Linux, keep `kb serve --no-open` running yourself; `kb wait` and the board check once a second there.

For your own alerts on a phone, Slack or anything else, add a command to `bento.json` in your workspace. It receives the event as JSON on stdin, plus `$BENTO_TITLE` and `$BENTO_MESSAGE`:

```json
{ "notify": { "command": "curl -s -d \"$BENTO_MESSAGE\" https://ntfy.sh/your-private-topic" } }
```

## License

[MIT](LICENSE)
