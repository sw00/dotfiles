# WT — worktrees and workstreams (`wt`)

[worktrunk](https://github.com/max-sixty/worktrunk) owns git worktrees. It replaced
`pwt`, which also owned tmux windows, pinned pi session ids, agent state and secret
forwarding — all of that is now the shell's job, because a workstream window is an
ordinary shell rather than a spawned `pi`.

## The daily loop

```fish
wt switch --create feature    # branch + __worktrees/feature, cd needs shell integration
creds pi -c                   # the agent, with credentials, continuing this directory
wt remove feature             # when done — refuses on uncommitted changes
wt list                       # every worktree, with agent markers
```

Tmux is not involved: open a window where you want it (`prefix c`) and move between
workstreams with `prefix w` — pi titles its own windows.

## Credentials

No credential is exported at shell startup (L0, `docs/AGENT-SAFETY.md`). A workstream
shell has none until asked, and the asking is `creds` — a **fish function**, so the entry
point is always an interactive fish shell:

- `creds pi -c` — one command's worth. The values never touch this shell, but pi's own
  children (every shell tool, every subagent) do inherit them.
- bare `creds` — loads into this shell. Avoid it in a workstream: everything started
  there then inherits the values.

A running agent keeps the environment it started with, so a rotated token needs pi
restarted (`C-c`, `creds pi -c` again).

## Two rules

- **Never `wt remove --force`.** The installable version (0.81.0) has no
  `refs/wt-backup`, so `--force` discards uncommitted work irrecoverably. A plain
  `wt remove` refuses on uncommitted tracked changes and says what to run instead;
  `git stash -u` in that worktree is the one-shot escape — and note it does NOT take
  ignored files. Upstream documents that 0.82 restores the backup; nothing here relies
  on it.
- **Ignored files are not protection.** A worktree holding only `.env` and
  `node_modules/` is removed by a plain `wt remove`, deleting both silently. Keep
  per-worktree state out of worktrees; credentials are `creds`' job.

## Layout

Worktrees live at `<repo>/__worktrees/<branch>`, from the stowed
`~/.config/worktrunk/config.toml` template: inside the repo, so they stay under the path
prefix pi trusts and under the sesh/zoxide scope `repo-list` excludes. git does not treat
that directory as ignored on its own, so the user `post-start` hook `~/bin/wt-exclude`
adds it to the clone's `info/exclude` — never to `.gitignore`, which would force a commit
into every repo.

The hook pads a missing final newline before appending: without that, a last line such as
`node_modules/` would merge with `__worktrees/` and **stop** ignoring `node_modules`. It
also runs in the background, so `__worktrees/` stays untracked for a second or two after
a creation — `git add -A` inside that window stages it as a gitlink. And because the rule
lives in the exclude file, `git clean -X` sees it: a single `-f` skips the directory as a
nested repository, a double force deletes a live worktree.

Agent state comes from worktrunk's pi extension (`wt config plugins pi install`, which
writes the host-local `~/.pi/agent/extensions/worktrunk.ts`): `🤖` while working, in
`wt list`.

The desktop push is separate and pi-native: `agent/extensions/settle-notify.ts` notifies
when an agent settles or blocks, so a workstream that finishes while you are looking
elsewhere says so. `PI_SETTLE_NOTIFY=0` mutes it. It is the one behaviour worth keeping
from the old tmux tap — the tmux status bar itself still carries no agent state.

## Installing on a host

```sh
mise install                     # pins aqua:max-sixty/worktrunk@0.81.0
stow --restow --no-folding -d base -t ~ worktrunk
wt config shell install fish     # interactive; wrapper + completions
wt config plugins pi install     # interactive
```

0.82.0 does not install at all: it is signed by a release-recovery tag and fails mise's
cosign verification. The pin moves only when aqua's `latest` installs clean.
