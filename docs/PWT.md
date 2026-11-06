# PWT — pi workstreams (git worktree + tmux window + pinned session)

`pwt` runs several mutating pi agents in one repo without them colliding. Sessions
alone do not give that: several pi processes in one checkout share a working tree, so
they overwrite each other's files. A git worktree does — native git, no new tool.

Two surfaces, one owner: the `pwt` fish function does everything (create, remove,
jump), while the `C-w` panel decides *what* to act on, delegates every lifecycle
action to `pwt`, and re-attaches the state tap as it opens. There is one place that
pins a session id, and this is it. What follows is the contract plus the mechanism you
need to change the code safely; the incidents behind each rule are in
`docs/GOTCHAS.md` under `## pwt`.

## Verbs

| verb | what it does |
| `pwt <slug> [base]` | worktree at `<repo>/__worktrees/<slug>`, tmux window named after the slug in the repo's own session (the caller's, if the repo has no session), `pi --session-id <repo>-<slug>` |
| `pwt here <label>` | a workstream in the CURRENT checkout, no worktree (see below) |
| `pwt rm [--stash] <slug>` | remove worktree + branch. Bare: refuses while a window holds it or ignored files are present. `--stash`: closes the window, stashes changes, parks ignored files, then removes (see below) |
| `pwt close <dir>` | end a LIVE workstream: close the pi window at `<dir>` |
| `pwt jump <dir>` | go to the pi window whose pane cwd is `<dir>`, moving a pwt window back into its repo's session on the way (see below) |
| `pwt reload [--force] <dir>` | restart the pi window at `<dir>` against the current `secrets/env.fish` (see below) |
| `pwt revive [--dry-run] <dir>…` | re-open pi in a worktree window a tmux-resurrect restore left as a bare shell (see below) |
| `pwt ls` | list workstreams from a shell — the panel's own rows, in its order |
| `pwt ls --all` | read-only dormant listing per repo under `$PWT_SRC`: kept branches, `pwt` stashes, parked `pwt-removed/` dirs |
| `pwt help` | usage |

`pwt ls` prints `<label>\t<path>\t<wt|live>`, the panel's `--list` contract, so a
script and the panel cannot disagree about what exists. `pwt ls --all` is its
counterpart for what a teardown leaves behind, and the one listing the panel
deliberately does NOT print — a dormant row is not a jump target. It is read-only git
and prints a repo only when a section is non-empty: branches with no
`__worktrees/<slug>` worktree (re-running `pwt <slug>` checks one back out), stashes
whose message contains `pwt`, and the entries under `<git-common-dir>/pwt-removed/`.

Re-running `pwt <slug>` is the resume path: an existing window is reused, never
duplicated — **unless a tmux-resurrect restore left it as a bare shell**, which has
neither the `@pwt_sid` marker nor a durable pi title, so `pwt <slug>` must ADOPT it by
path instead (see “After a tmux-resurrect restore”). Two pi processes on one
`--session-id` open the SAME transcript JSONL and each rewrites it from its own memory,
so the duplicate silently loses turns. That is why the window records `@pwt_sid` +
`@pwt_dir`; the cwd is the fallback, for windows that predate the marker and for a pi
adopted at the worktree root. `__pwt_window_for` matches on the pair too — that is how
`pwt rm` decides a worktree is in use.

## Where the window opens

A workstream window lands in the tmux session that owns the repo's **main checkout**,
not in whichever session you happened to be sitting in, so a worktree appears beside
the project it belongs to (reuse has always teleported to its window).

The session is resolved from `session_path`, which tmux records when the session is
created (`sesh connect <path>` runs `new-session -c <path>`). It is READ, never guessed
from live pane cwds: panes `cd`, and a scratch session is routinely the one holding
worktree panes, so matching any path *inside* the tree resolves that session as the
parent of the repo whose worktree it holds (`GOTCHAS`: how that shipped). Order: a
session whose recorded path is the repo root — ANY such session claims the workstream,
and one *named* after the repo wins a tie, because that is the one your own switchers
pick; else a session named exactly the repo basename, which catches a start directory
that has wandered; else the session you are in, which is the answer when a repo has no
project session at all.
pwt never creates a session: that stays sesh's job (`C-f`/`C-o`/`C-j`), and a second
creator would be a second session manager. "No project session" is a normal outcome, not
an error. Both sides are canonicalised before comparing (`GOTCHAS`: why `path resolve`,
not `cd …; pwd -P`), and the session is TARGETED by id, the name tier matched with `=`
(exact), since tmux treats a bare name as a prefix. When the window lands elsewhere, pwt
moves your client with it (`switch-client`, then `select-window`): a bare `select-window`
cannot cross sessions and would look like it did nothing (`GOTCHAS`).

Placement is also **maintained**: a workstream that fell back to the caller's session
moves home the next time you go to it — re-running `pwt <slug>` or `pwt jump <dir>`,
which is what the panel's `enter` runs. That is why there is no "snap" verb. Windows
pwt did not open are never moved (the `@pwt_sid` check sits in the one place both verbs
pass through), a move insists on the recorded path rather than a matching name (another
repo can share a basename), and a move that would change nothing says nothing. If the
moved window is the only one in its session, that session ends with it
(`detach-on-destroy` is on by default), so pwt moves your client first and says which
session is going away.

## The panel: tmux prefix then `C-w`

Rows are every worktree under `$PWT_SRC` (default `~/src`) plus every live pi window
(pi titles itself `<APP_TITLE> - …`; the accepted prefixes are the `pwt-pi-titles`
set — `π - ` upstream, `Pi-Bolt - ` under the default `pi` on PATH — and
`PWT_PI_TITLE` overrides the set with one exact prefix), sorted so work that wants
a human comes first: `!` blocked, `✓` done, `x` error, `◔` working. `▸` means a
window is open on it, `⬤` means it has a transcript on disk. Cells are separated by a
space — `▸ ⬤ ◔ label` — because `⬤` fills its cell edge to edge.

No glyph may be missing from the terminal font or East-Asian-Ambiguous (it shifts the
fixed column), and `!`/`x` stay ASCII because those states also reach the status bar.
Which candidate failed for which reason: `GOTCHAS`.

| key | action |
| `enter` | go to the open window, else open one |
| `ctrl-t` | new worktree in the highlighted row's repo |
| `ctrl-r` | pick any other repo (worktree, or a workstream in place) |
| `ctrl-x` | end it — one `y/N`: closes the window; a worktree is stashed and removed |
| `ctrl-s` | reload it — one `y/N`: restart the row's pi with the current secrets env (an open window of either kind, so a `▸` worktree row works too; a mid-turn agent is still refused, see above) |

The preview answers "do I still need this?": `git status --short --branch`,
`· already in <default>` when HEAD is ancestry of the default branch, then the commits
that exist on **no remote** — because `--branch` only reports ahead/behind against an
upstream, and a worktree branch made from `HEAD` has none, so landed,
pushed-but-unmerged and local-only work are three distinguishable states. Two honest
limits: the wording is `already in`, not `merged`, since a fresh worktree on the
default branch qualifies too; and the ref is the last fetched one, as nothing here runs
`git fetch`, so a merge — or a squash-merge, never an ancestor — reads as unlanded.
Nothing here merges, and `pwt rm` keeps such a branch.

The four verbs sit on keys fzf's line editor leaves alone; `--expect` *takes* whatever
it is given, so `ctrl-n`/`ctrl-p` (next/previous match) stay navigation. That is why
reload is `ctrl-s` and not the obvious `ctrl-l` — fzf binds that to clear-screen. An
action closes the panel: the price of keeping the row and the query out of a shell
command string. Typing a slug is prompted after it closes, with what you typed offered
as the default (`--print-query`); an empty answer accepts it. `pwt` re-validates the
slug (the panel only reserves its own verb names), so a refusal keeps the popup open.

## After a tmux-resurrect restore

`C-r` brings sessions, windows and layout back, but a pwt window comes back as a
**bare shell** — resurrect saves the pane's children, saves no `@user` options, and the
shell it starts overwrites the restored title (`GOTCHAS`: the mechanism, verbatim). Left
alone, `C-w` → enter and `pwt <slug>` would open a SECOND window and orphan the restored
one. Two surfaces repair it:

- **`pwt <slug>` / the panel's `enter`** adopt a restored window: same pane, same
  window, `pi` respawned into it and the identity re-marked. The worktree PATH carries
  the identity (`<root>/__worktrees/<slug>` → `<repo basename>-<slug>`).
- **`pwt revive <dir>…`** is the same repair as an explicit verb; `--dry-run` reports
  what it would do and changes nothing.

By default `C-r` also triggers a post-restore hook (`@resurrect-hook-post-restore-all`
→ `~/bin/pwt-revive-restored`) that reads the save file's **saved pane titles** and
revives only the paths a pane that WAS pi occupied — a shell merely `cd`'d into a
worktree at save time is left alone. `tmux set -g @pwt_revive 0` mutes the hook; the
`pwt revive` verb keeps working (the switch is read only by the hook). The hook never
`switch-client`s or moves windows, because `post-restore-all` fires last and a jump
there would undo the session resurrect just chose.

A revive only ever touches a pane that is a bare, IDLE shell whose cwd is exactly the
worktree path: a live pi, a shell with a child (a hand-started pi), a marked
workstream, the pane `pwt` runs in, and a worktree with more than one idle pane are all
refused. `comm(pane_pid)` + no children is the discriminator; `pane_current_command`
lies (`GOTCHAS`). See `TODO.md`.

**Adoption outranks the title in `pwt <slug>`**: a title is a prefix any shell can
carry, so idle-shell evidence at the worktree path is trusted FIRST and the title only
decides what is left. And **the pane `pwt` is typed into is refused, never duplicated**:
a bare shell in the worktree root cannot be respawned without killing the `pwt` running
in it, and a shell that merely `cd`'d in is indistinguishable from a restored one — get
in through the panel's `enter` (a popup, so it has no such pane) or from another pane.

## Worktree vs in-place

`pwt here` exists for repos a fresh checkout cannot serve: a git-crypt repo fails
`worktree add` at the smudge filter and the new tree would need its own unlock, and
per-path state (`.env`, `.venv`, `node_modules`, `direnv allow`) does not carry into a
worktree anyway.

The catch is stated in the command's output whenever a pi is already open in that
checkout itself (a pi in one of its worktrees does not count): two in-place workstreams
share one working tree, so parallel edits WILL collide. Nothing warns you the first
time — that is the rule, not an oversight. It warns rather than refuses because
refusing would delete the rung's reason to exist.

## Changing the environment

A workstream window runs `pi --session-id <sid>` directly — there is no shell in it —
so nothing re-reads `secrets/env.fish` for the pi's lifetime, and a running process can
never be handed new variables (the env is fixed at exec; only a restart changes it).
pwt therefore hands the values to the spawn itself, as tmux `-e NAME=VALUE` arguments:

- **Names** come from the `set -gx NAME …` lines of `~/dotfiles/secrets/env.fish`
  (`PWT_SECRETS` points at a different file; `PWT_FORWARD_ENV` replaces the list
  outright, and those names keep the calling shell's values — one it does not export
  is skipped). Only anchored lines count — the file carries commented-out `set -gx`
  lines for retired keys — and a name whose value is empty is skipped rather than
  forwarded as empty, because `-e NAME=` would CLEAR it.
- **Values** are read from that file at the moment of the call, not from the calling
  shell's exports, which are routinely older than the edit.
- `TERM`, `TMUX`, `TMUX_PANE`, `PWD`, `OLDPWD`, `HOME` and `PATH` are never forwarded:
  tmux requires its own `TERM`, and `tmux.conf` seeds the server's `PATH` with the
  mise shims.

So an edit needs no new shell for the pi — only a restart:

```
pwt reload <dir>            # re-exec pi in that workstream's window
pwt reload --force <dir>    # ...even while it is mid-turn
```

`pwt reload` is a restart, not a patch: the in-flight turn is lost, the transcript is
resumed by the re-run `--session-id`, and the window keeps its name, its pane and its
`@pwt_*` markers. It restarts in the workstream's OWN directory, so a pi that had
`cd`'d inside it is not where the new pi starts. It refuses a window pwt did not open
(there is no session id to resume — use `pwt close <dir>` and the usual pwt command
instead) and a pane whose agent is `working` unless `--force`. The values are
deliberately NOT pushed into the tmux server (`tmux setenv -g`): such a value outlives
the command and is inherited by every later window on the server, including ones pwt
did not open, with nothing that ever clears it. The refreshed exports also land in the
calling shell; that is idempotent and expected (`GOTCHAS`).

Requires tmux 3.2 or newer for `-e` (WSL's apt tmux 3.4 is above that); below it the
spawn is rejected rather than degraded. Secrets therefore appear in the tmux command
line for a moment (`ps`), which is fine on a single-user machine but worth knowing.
pi's session tools inherit the environment too, so a rotated token needs the same
reload. The panel's `ctrl-s` is that same verb for the highlighted row; `enter` still
reuses a window without restarting it.

## What pwt leaves on disk

- `<repo>/__worktrees/<slug>` — the worktree. Staying inside the repo keeps it under
  the trusted path prefix in `~/.pi/agent/trust.json`.
- `__worktrees/` in `<git-common-dir>/info/exclude`. Per-clone, uncommitted: without it
  `git status` shows the directory, `git add -A` stages a gitlink for the worktree and
  ripgrep/editors index every copy. Editing the repo's `.gitignore` instead would force a
  commit into every repo you use pwt in. Written on create, never removed by `pwt rm`.
  Side effect: it is now ignored, so `git clean -X` considers it — one `-f` skips a
  nested repository, a double force deletes a live worktree (`GOTCHAS`).
- The branch named after the slug.
- After `pwt rm --stash`: one stash entry per removed worktree (`git stash list`) and
  `<git-common-dir>/pwt-removed/<slug>-<stamp>/` holding whatever was ignored. Both are
  yours to delete once you are sure. `pwt ls --all` lists all three — the kept branch
  included — so a recovery surface exists after the worktree and window are gone.

## Removal

`pwt rm` is the conservative form, for a shell: it refuses while a window holds the
worktree, and while ignored files are present (`.env`, `.venv`, `node_modules` — `git
worktree remove` deletes those without a word). Both refusals name `--stash` as the way
out.

`pwt rm --stash` is what `ctrl-x` runs. One confirmation, then the whole teardown, in
an order chosen so every step is recoverable:

1. uncommitted tracked and untracked work is stashed onto the REPO's list — it
   survives this worktree and its branch (`git -C <repo> stash list`);
2. ignored files are **moved, never deleted**, to
   `<git-common-dir>/pwt-removed/<slug>-<UTC stamp>/`, where git status, ripgrep and
   the panel will not see them (a rename, so a `node_modules` costs nothing);
3. the window holding the worktree is closed **last**, so a popup that dies with it
   cannot leave a half-dismantled tree;
4. the worktree is removed and the branch deleted — but an **unmerged branch is
   kept**, because those commits exist nowhere else.

Re-running `pwt <slug>` (without a base ref) checks a kept branch back out. `pwt close
<dir>` is the same idea for a live workstream, minus the tree.

## State and notifications

pi reports `working/blocked/done/error/clear` over OSC 7501, with `app=pi` in the
report under BOTH variants, which is why `pwt-osc` filters on `pi` and needed no change
when bolt became the default (`GOTCHAS`). tmux consumes unknown OSC, so a `pipe-pane`
tap (`pwt-osc`) reads the pane's byte stream before tmux parses it and mirrors the state
into window options:

- `@pi_state` — what pi last said. Shown in the panel.
- `@pi_alert` — set when that state wants a human, and shown as `!` in the window
  list. The window list cannot tell the three apart, so its `!` means "wants a human"
  (blocked **or** done **or** error) while the panel's `!` is blocked only. It decays
  when you look at the window, so it reads as an inbox, not a log.
- A desktop notification for the same three states, at most once per workstream per
  5 minutes: a live agent settles many times on one task (`GOTCHAS` has the count), so
  without a cooldown one stuck agent is a notification storm. Never for a window you
  are already looking at. The title is `org/repo/<name> — state` (repo-relative to
  `$PWT_SRC` when the path is under it), because a push that says only `<name>` cannot
  be acted on when two repos hold a workstream of that name.

`tmux set -g @pwt_notify 0` mutes the pushes; the flag and the panel are unaffected.
The tap is attached by `pwt` when it opens a window, by `pwt jump`, and to every live pi
pane each time the panel opens — so a session started by hand gains state the first time
you look for it, and nothing needs to wrap `pi`. WSL pushes a WinRT toast through
`powershell.exe`; the failure mode is silence (see `TODO.md`). `PWT_NOTIFY_CMD`
replaces the transport for tests.

## Limits worth knowing

- `⬤` tests for a *transcript*, never for the session directory: an empty project dir is
  evidence of a lookup, not of history (invariant 5, and `GOTCHAS`).
- A session forked inside a pi — `/new`, `/fork`, `/clone`, or a handoff — is a NEW
  session id that pwt cannot see: the OSC 7501 tap carries state only, and resurrect
  does not save `@user` options. `pwt reload` therefore resumes the pinned id, not the
  fork; use pi's own `/resume` inside the window.
- Subagents are child processes of the pane's pi (`pi --mode json -p --no-session`,
  in-memory) — no transcript, no window, and their answer comes back as the parent's
  tool result. There is nothing for pwt to show, close or merge.
- `$PWT_SRC` is both the panel's worktree scan and the `C-f` picker's zoxide scope. A
  worktree created outside it (reachable through `ctrl-r`) is not a panel row once its
  window closes; `pwt rm <slug>` still works.
- `pi-prune-sessions` drops transcripts untouched for 90 days, so a workstream idle
  longer than that starts fresh. It is MANUAL ONLY — never schedule or auto-run it: the
  transcripts are the only source for session review and the `/usage` dashboard.
- Session ids are `<repo basename>-<slug>`, so they are not unique across repos — which
  is why windows carry `@pwt_dir` too.
- A workstream window lives in its project's session, so it dies with that session:
  prefix then `C-x` (the sesh kill-session popup — not the panel's `ctrl-x`) ends the
  project's workstream agents too. The transcript survives (pi persists per entry), so
  `pwt <slug>` resumes, but an in-flight turn is lost — and that is the point: the
  project owns its workstreams. Resurrect brings the WINDOW back, not the pi process
  (`@resurrect-processes` lists no `pi`), so re-running `pwt <slug>`, `pwt revive <dir>`
  or the post-restore hook respawns the agent in it.
- With more than one client attached, the client that moves is the one pwt was run from
  (`switch-client` is not given `-c`): any other client keeps what it was showing.

## If you change this

Ten invariants are load-bearing here: none of them is obvious from the line it
constrains. Read the comment before changing the line — the mechanism is written down
there, not just the rule. The incidents behind them are in `GOTCHAS`.

- **The pi title is a SET, written once as a `pwt-pi-titles:` marker line.** The same
  marker is byte-identical in `pwt-pick`, `pwt.fish` and `pwt-revive-restored`;
  `check.sh` asserts all three agree and exercises each consumer behaviourally against
  both prefixes. It is a set because `APP_TITLE` is a BUILD CONSTANT, not config, so
  Pi-Bolt cannot be made to say `π` (`GOTCHAS`). A third variant means adding its prefix
  in all three files; miss one and its panes silently vanish from the panel, or come
  back as bare shells after a restore. `PWT_PI_TITLE` REPLACES the set with one exact
  prefix — that is the fixture seam, and a predicate that also accepted the shipped pair
  would let fixtures pass for the wrong reason. Honest limit: a SHELL in a directory
  named `Pi-Bolt` titles itself `Pi-Bolt - fish` and matches, which is why the title
  never outranks idle-shell evidence.

- **One `respawn-pane`, in `__pwt_respawn_pi`.** `pwt reload` and `pwt revive` are the
  same restart (same pane, same env flag, same `pane_dead` survival check, same tap
  re-attach); a second copy drifts, and `check.sh` asserts the count is one.
- **A restored pane is adopted only when it is an IDLE shell** — `comm(pane_pid)` is a
  shell (login `-sh` included) and it has no children. A pi title is a prefix a shell
  can carry, so it must never outrank that evidence in `pwt <slug>`; a pane with a
  child, a marked workstream, a non-shell, or the pane `pwt` runs in is never respawned.
  Note what makes a live pi "not a shell" here: `__pwt_is_shell` is a SHELL ALLOWLIST,
  so `node` (upstream pi) and `pi-bin` (Pi-Bolt) are excluded without naming either —
  never convert it to a blocklist of one variant's comm.

- **Window identity is `@pwt_sid` + `@pwt_dir` together.** The sid comes from the repo
  basename, so on its own it is not unique across repos or between `here` and a
  worktree. The pre-marker fallback is restricted to unmarked windows whose pane cwd is
  inside the tree; an unconditional sid match silently teleports into the other
  workstream.
- **`⬤` reads a TRANSCRIPT, never a session DIRECTORY.** pi `mkdirSync`s the project
  session dir on any session *resolve* (`getDefaultSessionDir`) and writes nothing until
  the first turn, so `-d` claimed history for worktrees that never had a conversation.
  `has_history` globs `*.jsonl` instead (bash 3.2: no `find -quit`).
- **`list-panes`, never `list-windows`** for "where is this workstream" — window
  formats report the ACTIVE pane's cwd (`GOTCHAS`).
- **`info/exclude`, never `.gitignore`** — see "What pwt leaves on disk" for why and
  the trailing-newline rule; the parent-directory rule is in `GOTCHAS`.
- **`pipe-pane` without `-o`**, and **`#{pane_id}` never a literal pane id**: `-o`
  detaches the tap on a re-attach, and the command string passes through strftime
  first, where `%3` becomes `3` (`GOTCHAS` has the silent-wrong-window part).
- **Anything fzf runs — `--preview`, `execute(...)` — runs under `$SHELL`**, which is
  fish here. Keep it to one line all three shells parse, or put it in a script; the
  panel's preview is `pwt-preview` for exactly this reason. Tab-separated records need
  a placeholder for every optional field, because `read` collapses empty ones.
- **The parent session is read from `session_path`, never from a pane cwd or any path
  inside the tree.** sesh records it at session creation; an observed tier resolves a
  session that merely HOSTS worktree panes as the parent of the repo whose worktree it
  holds, which puts the window in a scratch session — the placement this feature exists
  to end (and what `no-worktrees` prevents in `__pwt_window_for`). Target it by session
  ID with `=name` on the name tier: a bare name is a prefix match, and tmux rewrites
  `.`/`:` in names.
Where the guarantees live: `bash check.sh`. The pwt blocks cover the identity tiers,
both collision directions, the ignore write, the window's session placement (against a
private server whose sessions stand in a repo root, elsewhere, and inside a worktree),
the panel parser, the push decisions and the preview — several against a private tmux
server and a stub `pi`, so they run without touching your session.
## Not built, on purpose

A dashboard, prompt injection, merge automation, bulk multi-remove, a persistent panel,
and clickable notifications. `workmux` does those; it was trialled and deferred
(`TODO.md`), and the gap it left was agent *status*, which the tap fills. Revisit only
if manual bookkeeping costs more than ~10 minutes a week.
