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
script and the panel cannot disagree about what exists.

`pwt ls --all` is the counterpart for what a teardown leaves behind, and is the one
listing the panel deliberately does NOT print — a dormant row is not a jump target.
It is read-only git (no tmux, so it works from a plain terminal) and walks the repos
under `$PWT_SRC`, printing a repo only when at least one section is non-empty: local
branches that have no `__worktrees/<slug>` worktree (any of which re-running
`pwt <slug>` checks back out), `git stash list` entries whose message contains
`pwt`, and the entries under `<git-common-dir>/pwt-removed/`.

Re-running `pwt <slug>` is the resume path: an existing window is reused, never
duplicated — **unless a tmux-resurrect restore left it as a bare shell**, which has
neither the `@pwt_sid` marker nor a durable pi title, so `pwt <slug>` cannot recognise
it and must ADOPT it by path instead of opening a second window (see “After a
tmux-resurrect restore”). Duplicating would be worse than untidy — two pi processes
on one
`--session-id` open the SAME transcript JSONL and each rewrites it from its own
memory, so turns are silently lost. That is why the window records `@pwt_sid` +
`@pwt_dir`; the cwd is only a fallback, for windows that predate the marker and for a
pi adopted at the worktree root. (`__pwt_window_for` also matches on it — that is how
`pwt rm` decides a worktree is in use.)

## Where the window opens

A workstream window lands in the tmux session that owns the repo's **main checkout**,
not in whichever session you happened to be sitting in — so a worktree appears beside
the project it belongs to, and creating a workstream behaves like reusing one (which
has always teleported to its window).

The session is resolved from `session_path`, which tmux records when the session is
created (`sesh connect <path>` runs `new-session -c <path>`). It is READ, never
guessed from live pane cwds: panes `cd`, and a scratch session is routinely the one
holding worktree panes — so a match on any path *inside* the tree would resolve that
session as the parent of the very repo whose worktree it holds. Order:

1. a session whose recorded path is the repo root — ANY session started at the root
   claims the workstream, sesh-made or hand-made (one *named* after the repo wins a
   tie, since that is the one your own switchers pick);
2. a session named exactly the repo basename (catches a session whose start
   directory has wandered, or one made by hand);
3. otherwise the session you are in — the pre-existing behaviour, and the answer when
   a repo has no project session at all.

pwt never creates a session: that stays sesh's job (`C-f`/`C-o`/`C-j`), and a second
creator would be a second session manager. "No project session" is a normal outcome,
not an error. Both sides are canonicalised before comparing, because tmux reports
`session_path` as given (`/tmp` where git says `/private/tmp` on macOS) — the same
lesson as `__pwt_window_for`. The canonicaliser is a `path resolve` call: doing it with
`cd …; pwd -P` would fire a PWD-change event (which direnv hooks on) once per session
on the server, and the shell then has to be put back.

The session is TARGETED by id, and the name tier is matched with `=` (exact): tmux
rewrites `.` and `:` in a session name, cannot reach a name beginning with `$` at all,
and treats a bare name as a prefix — `foo` would answer from `foobar`.

When the window does land elsewhere, pwt moves your client with it
(`switch-client`, then `select-window`): a bare `select-window` cannot cross sessions,
and the command would look like it did nothing at all.

Placement is also **maintained**, not decided once. A workstream that had to fall back
to the caller's session (its project session did not exist yet) moves home the next
time you go to it — re-running `pwt <slug>`, or `pwt jump <dir>`; the panel's `enter`
is both of those, so it is the usual trigger. That is why there is no "snap" verb: the
verbs that reach a workstream are already the ones that know where it belongs. Windows
pwt did not open are never moved — the `@pwt_sid` check sits in the one place both
verbs go through, so the pane-cwd fallback that can find a hand-started pi inside a
worktree never drags it across sessions — and a move that would change nothing says
nothing. A move also insists on the recorded path rather than a matching session name:
tier 2 below is fair evidence when CREATING (the window has to go somewhere), but
another repo can share a basename, and that is not worth stealing a window for.

One consequence: if the moved window is the only one in its session, that session ends
with it. `detach-on-destroy` is on by default, so pwt moves your client first and says
which session is going away.

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
| `ctrl-x` | end it — one `y/N`: closes the window; a worktree is stashed and removed |
| `ctrl-s` | reload it — one `y/N`: restart the row's pi with the current secrets env (live rows only; a mid-turn agent is still refused, see above) |

The preview is the "do I still need this?" panel: `git status --short --branch`, then
the commits that exist on **no remote**. The second half matters because `--branch`
only reports ahead/behind against an upstream, and a worktree branch made from `HEAD`
has none — so merged-and-pushed is visible, local-only work is visible, and landing is
your call. Nothing here merges.

The four verbs sit on keys fzf's line editor leaves alone; `--expect` *takes*
whatever it is given, so `ctrl-n`/`ctrl-p` (its next/previous match) stay navigation.
That is why reload is `ctrl-s` and not the obvious `ctrl-l` — fzf binds that to
clear-screen. An action closes the panel — the price of keeping the row and the query
out of a shell command string.

Typing a slug is prompted after the panel closes, with what you typed as a filter
offered as the default (`--print-query`): filter to the name, `ctrl-t`, Enter. An
empty answer accepts the suggestion, anything you type replaces it, and `ctrl-c`
aborts. `pwt` re-validates it (the panel only reserves its own verb names), so a
refusal keeps the popup open to be read.

## After a tmux-resurrect restore

`C-r` brings sessions, windows and layout back, but a pwt workstream window comes back
as a **bare shell**: resurrect's default save strategy records the CHILDREN of the pane
pid, and a pwt pane runs `pi --session-id <sid>` with no shell, so its saved command is
empty; `@user` options (`@pwt_sid`, `@pwt_dir`, the OSC tap) are not saved either; and
the `π - <slug>` title resurrect restores is overwritten by the shell. Left alone,
`C-w` → enter and `pwt <slug>` would open a SECOND window and orphan the restored one.

Two surfaces repair it:

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
worktree path: a live pi (`node`), a shell with a child (a hand-started pi), a marked
workstream, the pane `pwt` runs in, and a worktree with more than one idle pane are all
refused. `comm(pane_pid)` + no children is the discriminator — `pane_current_command`
lies, because tmux wraps a window command in a shell. See `TODO.md`.

Two consequences worth knowing. **Adoption outranks the title**: the `π - ` prefix is
what a restored shell can spoof, so demonstrable idle-shell evidence at the worktree
path is trusted FIRST and the pane title only decides what is left — that is why a
restored pane is revived rather than jumped to. And **the pane `pwt` is typed into is
refused, never duplicated**: a bare shell sitting in the worktree root cannot be
respawned without killing the `pwt` running in it, so `pwt <slug>` says so rather than
opening a second window. A shell that merely `cd`'d into a worktree root is
indistinguishable from a restored one and is refused the same way — get in through the
panel's `enter` (a popup, so it has no such pane) or from another pane.

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
`cd`'d somewhere inside it (or the shell tab you opened next to it) is not where the
new pi starts. It refuses a window pwt did not open (there is no session id to
resume — use `pwt close <dir>` and the usual pwt command instead) and a pane whose
agent is `working` unless `--force`.

Side effect to know: re-reading the file happens in pwt's own process, so the shell
that ran `pwt` or `pwt reload` also gets the refreshed exports (fish 4.9.3 propagates
`set -gx` out of the command substitution pwt builds the arguments in) — the same file,
at the same path, that it sourced at startup, so it is idempotent. The values are
deliberately NOT pushed into the tmux server (`tmux setenv -g`): such a value outlives
the command and is inherited by every later window on the server, including ones pwt
did not open, with nothing that ever clears it.

Requires tmux 3.2 or newer for `-e` (WSL's apt tmux 3.4 is above that); below it the
spawn is rejected rather than degraded. Secrets therefore appear in the tmux command
line for a moment (`ps`), which is fine on a single-user machine but worth knowing.
pi's own session tools inherit the environment too, so a rotated token needs the same
reload before they see it. The panel's `ctrl-s` is that same verb for the highlighted
row; `enter` still reuses a window without restarting it.

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
- After `pwt rm --stash`: one stash entry per removed worktree (`git stash list`) and
  `<git-common-dir>/pwt-removed/<slug>-<stamp>/` holding whatever was ignored. Both are
  yours to delete once you are sure. `pwt ls --all` lists all three — the kept branch
  included — so a recovery surface exists after the worktree and window are gone.

## Removal

`pwt rm` is the conservative form, for a shell: it refuses while a window holds the
worktree, and while ignored files are present (`.env`, `.venv`, `node_modules` — `git
worktree remove` deletes those without a word). Both refusals name `--stash` as the
way out.

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

Re-running `pwt <slug>` (without a base ref) checks a kept branch back out, so the
work is not lost. `pwt close <dir>` is the same idea for a live workstream, minus the
tree: it closes the pi window and nothing else.

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
- `pi-prune-sessions` drops transcripts untouched for 90 days, so a workstream idle
  longer than that starts fresh. It is MANUAL ONLY — never schedule or auto-run it:
  the transcripts are the only source for session review and the `/usage` dashboard.
- Session ids are `<repo basename>-<slug>`, so they are not unique across repos. pi
  namespaces transcripts by project directory, so that is only a window-handle
  concern — which is why windows carry `@pwt_dir` too.
- A workstream window now lives in its project's session, so it dies with that
  session: prefix then `C-x` (the sesh kill-session popup — not the panel's `ctrl-x`)
  ends the project's workstream agents too. The transcript survives (pi persists per
  entry), so `pwt <slug>` resumes — but an in-flight turn is lost. That is also the
  point: the project owns its workstreams. Note resurrect brings the WINDOW back, not
  the pi process (`@resurrect-processes` lists no `pi`), so a restored window comes
  back with a shell, not an agent: re-running `pwt <slug>` or `pwt revive <dir>` — or
  the post-restore hook — respawns the agent in it (see “After a tmux-resurrect
  restore”).
- With more than one client attached, the client that moves is the one pwt was run from
  (`switch-client` is not given `-c`): any other client keeps what it was showing, and
  loses its place only if its own session is the one a move empties.

## If you change this

Eight invariants are load-bearing here: none of them is obvious from the line it
constrains. Read the comment before changing the line — the mechanism is written down
there, not just the rule.

- **One `respawn-pane`, in `__pwt_respawn_pi`.** `pwt reload` and `pwt revive` are the
  same restart (same pane, same env flag, same `pane_dead` survival check, same tap
  re-attach); a second copy drifts, and `check.sh` asserts the count is one.
- **A restored pane is adopted only when it is an IDLE shell** — `comm(pane_pid)` is a
  shell (login `-sh` included) and it has no children. The `π -` title is a prefix a
  shell can carry, so it must never outrank that evidence; and a pane with a child, a
  marked workstream, a non-shell, or the pane `pwt` runs in is never respawned.

- **Window identity is `@pwt_sid` + `@pwt_dir` together.** The sid comes from the repo
  basename, so on its own it is not unique across repos or between `here` and a
  worktree. The pre-marker fallback is restricted to unmarked windows whose pane cwd is
  inside the tree; an unconditional sid match silently teleports into the other
  workstream.
- **`list-panes`, never `list-windows`** for "where is this workstream" — window
  formats report the ACTIVE pane's cwd (`GOTCHAS`).
- **`info/exclude`, never `.gitignore`** — see "What pwt leaves on disk" for why and
  the trailing-newline rule; the parent-directory rule is in `GOTCHAS`.
- **`pipe-pane` without `-o`**, and **`#{pane_id}` never a literal pane id**: `-o`
  detaches the tap on a re-attach, and the command string passes through strftime
  first, where `%3` becomes `3`.
- **Anything fzf runs — `--preview`, `execute(...)` — runs under `$SHELL`**, which is
  fish here. Keep it to one line all three shells parse, or put it in a script; the
  panel's preview is `pwt-preview` for exactly this reason. Tab-separated records need
  a placeholder for every optional field, because `read` collapses empty ones.
- **The parent session is read from `session_path`, never from a pane cwd or any path
  inside the tree.** sesh records it at session creation; an observed tier resolves a
  session that merely HOSTS worktree panes as the parent of the repo whose worktree it
  holds, which puts the window in a scratch session — the placement this feature
  exists to end (and what `no-worktrees` prevents in `__pwt_window_for`). Target it by
  session ID with `=name` on the name tier: a bare name is a prefix match, and tmux
  rewrites `.`/`:` in names.

Where the guarantees live: `bash check.sh`. The pwt blocks cover the identity tiers,
both collision directions, the ignore write, the window's session placement (against a
private server whose sessions stand in a repo root, elsewhere, and inside a worktree),
the panel parser (including the no-state tap), the push decisions and the preview —
several of them against a private tmux server and a stub `pi`, so they run without
touching your session.

## Not built, on purpose

A dashboard, prompt injection, merge automation, bulk multi-remove, a persistent
panel, and clickable notifications. `workmux` does those; it was trialled and
deferred (`TODO.md`), and the gap it left was agent *status*, which the tap fills.
Revisit only if manual bookkeeping costs more than ~10 minutes a week.
