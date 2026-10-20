# PWT — pi workstreams (git worktree + tmux window + pinned session)

`pwt` runs several mutating pi agents in one repo without them colliding. Sessions
alone do not give that: several pi processes in one checkout share a working tree,
so they overwrite each other's files. A git worktree does — native git, no new tool.

Two surfaces, one owner: the `pwt` fish function does everything (create, remove,
jump), while the `C-w` panel decides *what* to act on, delegates every lifecycle
action to `pwt`, and re-attaches the state tap as it opens. There is one place that
pins a session id, and this is it.

## Verbs

| verb | what it does |
|---|---|
| `pwt <slug> [base]` | worktree at `<repo>/__worktrees/<slug>`, tmux window named after the slug, `pi --session-id <repo>-<slug>` |
| `pwt here <label>` | a workstream in the CURRENT checkout, no worktree (see below) |
| `pwt rm <slug>` | remove worktree + branch; refuses while a window holds it or ignored files are present |
| `pwt jump <dir>` | go to the pi window whose pane cwd is `<dir>` |
| `pwt ls` | list workstreams from a shell — the panel's own rows, in its order |
| `pwt help` | usage |

Re-running `pwt <slug>` is the resume path: an existing window is reused, never
duplicated. Duplicating would be worse than untidy — two pi processes on one
`--session-id` open the SAME transcript JSONL and each rewrites it from its own
memory, so turns are silently lost. That is why the window records the workstream
identity (`@pwt_sid` + `@pwt_dir`) instead of relying on a cwd guess. The cwd is
only a secondary signal, in two places: the tier for windows that predate the marker,
and `__pwt_open_window`'s fallback that adopts a pi already sitting exactly at the
worktree root. (`__pwt_window_for` uses it too, for "is this directory in use" —
that is how `pwt rm` decides.)

## The panel: tmux prefix then `C-w`

Rows are every worktree under `$PWT_SRC` (default `~/src`) plus every live pi window
(pi titles itself `π - …`; the prefix is `PWT_PI_TITLE`), sorted so work that wants
a human comes first: `⚑` blocked, `✓` done, `✗` error, `◐` working. `▸` means a
window is open on it, `●` means it has session history.

| key | action |
|---|---|
| `enter` | go to the open window, else open one |
| `ctrl-t` | new worktree in the highlighted row's repo |
| `ctrl-r` | pick any other repo (worktree, or a workstream in place) |
| `ctrl-x` | remove — prints what would be lost, asks `y/N` |

The preview is the "do I still need this?" panel: `git status --short --branch`, then
the commits that exist on **no remote**. The second half matters because `--branch`
only reports ahead/behind against an upstream, and a worktree branch made from `HEAD`
has none — so merged-and-pushed is visible, local-only work is visible, and landing is
your call. Nothing here merges.

Those three are keys fzf's own line editor does not use. `--expect` *takes* a key
away from the editor, so binding `ctrl-n`/`ctrl-d` (fzf's next-match and
delete-char) made navigation asymmetric and fired a name prompt on the
muscle-memory key. An action closes the panel; that is the price of keeping the
selected row and the typed query out of a shell command string.

Typing a slug is prompted after the panel closes, with what you typed as a filter
offered as the default (`--print-query`): filter to the name, `ctrl-t`, Enter. An
empty answer accepts the suggestion, anything you type replaces it, and `ctrl-c`
aborts. `pwt` re-validates it (the panel only reserves its own verb names), so a
refusal keeps the popup open to be read.

## Worktree vs in-place

`pwt here` exists for repos a fresh checkout cannot serve: a git-crypt repo fails
`worktree add` at the smudge filter and the new tree would need its own unlock, and
per-path state (`.env`, `.venv`, `node_modules`, `direnv allow`) does not carry into
a worktree anyway.

The catch is stated in the command's output whenever a pi is already open in that
checkout itself (a pi in one of its worktrees does not count): two in-place
workstreams share one working tree, so parallel edits WILL collide. Nothing warns you
the first time — that is the rule, not an oversight. It warns rather than refuses
because refusing would delete the rung's reason to exist. Use it for read-mostly
work, or one agent at a time.

## What pwt leaves on disk

- `<repo>/__worktrees/<slug>` — the worktree. Staying inside the repo keeps it under
  the trusted path prefix in `~/.pi/agent/trust.json`.
- `__worktrees/` in `<git-common-dir>/info/exclude`. Per-clone, uncommitted: without
  it `git status` shows the directory, `git add -A` stages a mode-160000 gitlink for
  the worktree (git treats it as an embedded repository) and ripgrep/editors index
  every copy. Editing the repo's `.gitignore` instead would force a commit into every
  repo you use pwt in. Written by `pwt` on create and never removed by `pwt rm`.
  Side effect to know: it is now ignored, so `git clean -X` considers it — a single
  `-f` skips it as a nested repository (verified: "Would skip repository"), but a
  double force would delete a live worktree.
- The branch named after the slug.

## Removal

`pwt rm` refuses in two cases, both deliberate:

- **A window still holds the worktree** (including a pane that cd'd into a
  subdirectory). Killing that window is its own act. Refusal prints the window id.
- **Ignored files are present** (`.env`, `.venv`, `node_modules`). `git worktree
  remove` deletes those without a word; they are exactly what a worktree
  accumulates, so losing them must be deliberate.

If the branch is not fully merged, the worktree is removed and the branch is kept —
correctly, those commits exist nowhere else. Merge it, then
`git -C <repo> branch -d <slug>`. Re-running `pwt <slug>` (without a base ref)
checks that branch back out, so the work is not lost.

## State and notifications

pi reports `working/blocked/done/error/clear` over OSC 7501. tmux consumes unknown
OSC, so a `pipe-pane` tap (`pwt-osc`) reads the pane's byte stream before tmux parses
it and mirrors the state into window options:

- `@pi_state` — what pi last said. Shown in the panel.
- `@pi_alert` — set when that state wants a human, and shown as `⚑` in the window
  list. It decays when you look at the window (any pane of it), so it reads as an
  inbox rather than a log.
- A desktop notification for the same three states, at most once per workstream per
  5 minutes — a live agent settles 7–22 times on one task, so without a cooldown one
  stuck agent is a notification storm. Never for a window you are already looking at.
  The title is `org/repo/<name> — state` (repo-relative to `$PWT_SRC` when the path is
  under it), because a push that says only `<name>` cannot be acted on when two repos
  hold a workstream of that name.

`tmux set -g @pwt_notify 0` mutes the pushes; the flag and the panel are unaffected.
The tap is attached by `pwt` when it opens a window, by `pwt jump`, and to every live
pi pane each time the panel opens — so a session started by hand gains state the
first time you look for it, and nothing needs to wrap `pi`.

WSL pushes a WinRT toast through `powershell.exe`; the failure mode is silence (see
`TODO.md`). `PWT_NOTIFY_CMD` replaces the transport for tests.

## Limits worth knowing

- `$PWT_SRC` is both the panel's worktree scan and the `C-f` picker's zoxide scope.
  A worktree created outside it (reachable through `ctrl-r`) is not a panel row once
  its window closes; `pwt rm <slug>` still works.
- `pi-prune-sessions` drops transcripts untouched for 30 days, so a workstream idle
  longer than that starts fresh.
- Session ids are `<repo basename>-<slug>`, so they are not unique across repos. pi
  namespaces transcripts by project directory, so that is only a window-handle
  concern — which is why windows carry `@pwt_dir` too.
- Nothing here is clickable or automatic. The preview shows what has not reached a
  remote; merging is a git operation you run yourself.

## If you change this

Five invariants are load-bearing here, and each has already been broken once. Read the
comment before changing the line: the mechanism is written down there, not just the
rule.

- **Window identity is `@pwt_sid` + `@pwt_dir` together.** The sid comes from the repo
  basename, so on its own it is not unique across repos or between `here` and a
  worktree. The pre-marker fallback is restricted to unmarked windows whose pane cwd is
  inside the tree; an unconditional sid match silently teleports into the other
  workstream.
- **`list-panes`, never `list-windows`**, for anything about where a workstream is —
  the window formats report the ACTIVE pane's cwd (`GOTCHAS`).
- **`__worktrees/` goes to `info/exclude`, never `.gitignore`** (that would force a
  commit into every target repo), written with a real trailing newline. Its parent-dir
  rule is in `GOTCHAS`.
- **`pipe-pane` without `-o`**, and **`#{pane_id}` never a literal pane id**: `-o`
  detaches the tap on a re-attach, and the command string passes through strftime
  first, where `%3` becomes `3`.
- **Anything fzf runs — `--preview`, `execute(...)` — runs under `$SHELL`**, which is
  fish here. Keep it to one line all three shells parse, or put it in a script; the
  panel's preview is `pwt-preview` for exactly this reason. Tab-separated records need
  a placeholder for every optional field, because `read` collapses empty ones.

Where the guarantees live: `bash check.sh`. The pwt blocks cover the identity tiers,
both collision directions, the ignore write, the panel parser (including the
no-state tap), the push decisions and the preview — several of them against a private
tmux server and a stub `pi`, so they run without touching your session.

## Not built, on purpose

A dashboard, prompt injection, merge automation, bulk multi-remove, a persistent
panel, and clickable notifications. `workmux` does those; it was trialled and
deferred (`TODO.md`), and the gap it left was agent *status*, which the tap fills.
Revisit only if manual bookkeeping costs more than ~10 minutes a week.
