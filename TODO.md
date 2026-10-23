<!-- Capture tier: TODO.md (analysis done, knock-off). See AGENTS.md §capture-tiers. -->

# TODO — open/deferred work

This file tracks only genuine open or deferred work; completed fixes were
removed — full implementation history lives in git. Shared-core behavior
(`base/`) is validated by `./check.sh`; run it before committing.

## Open — active bug

- [ ] **`pwt` hook test is nondeterministic (found 2026-10-23, same session it
  landed).** `check.sh`'s "pwt: the post-restore hook revives a pane whose SAVED title
  was pi's" passed, then failed, then passed again across three consecutive runs of
  UNCHANGED code (`651 passed / 0 failed` ↔ `650 passed / 1 failed`); the only edit
  between runs was doc-only. So the suite's green summary is a coin-flip on this
  assertion, which is worse than no assertion (AGENTS.md warns about exactly this).
  Hypothesis (UNVERIFIED): a fixture race — the demo8 pane is created and the hook run
  immediately after, and `__pwt_revive_panes` requires a SETTLED idle shell
  (`ps -o comm=` is a shell with no children), while `_rv_hook` also points
  `XDG_CONFIG_HOME` at an empty temp dir, so `fish -c 'pwt revive …'` may not autoload
  `pwt` at all in some runs. The flake is in the ASSERTION, not the product code, so
  the change set ships with it open — but characterize it before trusting a green
  summary: run the block under `bash -x` a few times, capture the hook's `hook-out`,
  and either settle the pane deterministically before the hook or make the assertion
  poll a bounded interval. Next action: reproduce with `_rv_hook`'s output preserved.

- [ ] **pwt workstream windows do not survive a tmux-resurrect restore (found
  2026-10-22).** `C-r` brings the sessions, windows and layout back, but a worktree
  window is a bare shell: resurrect records no command for a pane whose pid IS pi
  (its save strategy reads the pane pid's CHILDREN), no `@user` options are saved, and
  the `π -` pane title it does restore is a lie that `pi-only` believed — so
  `C-w` → enter either jumped to the shell or opened a second window and orphaned the
  first. Identity is recoverable from the path (`<root>/__worktrees/<slug>`).
  **Landed** (owner chose the auto-hook ON): `pwt revive [--dry-run] <dir>…` +
  `__pwt_revive`/`__pwt_revive_panes` in `base/fish/.config/fish/functions/pwt.fish`,
  adoption on the `pwt <slug>` path (panel `enter` runs it), the resurrect hook script
  `base/tmux/bin/pwt-revive-restored` wired via `@resurrect-hook-post-restore-all` with
  `@pwt_revive` as a kill switch, docs in `docs/PWT.md`, and behavioural + static
  assertions in `check.sh` (private socket, stub pi, restored panes built with
  `new-window -d -c` and no command). Design and mutant table:
  `.pi/plans/pwt-tmux-restore.md`. Open until a REAL `C-r` on a live server has been
  seen to revive: the suite drives the hook with a fabricated save file, so the
  save-file parse, the hook value (reproduced through resurrect's own `eval`) and the
  tmux wiring are covered, but the live restore is not.

- [ ] **`loop` smoke scenario no longer stops inside its signature (found
  2026-10-14, pi 1.2.0).** The eval's loop scenario should show <= 2 shell attempts
  and a stop quoting the verbatim error. Every run of the 2026-10-14 re-run took
  7-22 attempts (13/22/13/7/7) and ended by trying to *make* `false` exit 0 — a PATH
  shim in /tmp, `enable -n false`, probing shells, re-running under fish/zsh, and in
  one case searching the environment for a grader. `trivial` and `risky` held, so
  the regression is isolated to persistence on a task stated as impossible.
  Next action: separate harness from model — re-run the loop scenario alone with a
  different model (`PI_SMOKE_FLAGS="--model opencode-go/glm-5.3"`), and if it
  reproduces, against a pinned older pi (installed outside mise, since the mise copy
  is gone). Related: the prompt-slim watch below, which looks for exactly this
  "third attempt at the same fix" pattern in real use. Numbers:
  docs/PROMPT-EVAL.md §Re-baseline.

- [ ] **modes↔model-switch chat-mode restore.** Mitigated but open. A 429 on
  the chat model mid-`/chat` hops to its fallback twin, so `stillChatModel`
  stays false and the exit-chat restore is skipped. Next action: narrow the
  `stillChatModel` check in `base/pi/.pi/agent/extensions/modes/index.ts` to
  also accept the chat model's fallback twin (compare against the
  `rateLimitFallbacks` map); verify via `./check.sh`.
  Trigger check (2026-10-09): the hop is map-driven — `model-switch.ts:388-389`
  returns early when `rateLimitFallbacks` has no entry for the current model, and
  the handler's own comment (322-325) says an empty map makes auto-fallback a
  no-op. So it cannot fire on a profile whose map is empty (the one shipped here);
  it is reachable wherever the map is populated, which is the shared-core case
  that matters. Still worth fixing, deprioritizable for an attended profile.

- [ ] **pwt push notifications are unverified on WSL (2026-10-15).** Everything else
  about them is covered by `./check.sh`, including a live report through a real
  `pipe-pane`, but the WSL transport is a zero-dep WinRT toast run through
  `powershell.exe -NoProfile -NonInteractive -Command`, and its failure mode is
  SILENCE: a pipe-pane job's output is dropped, so a wrong snippet looks exactly like
  a working one until someone is on that machine. Next action: on a WSL host, `pwt
  <slug>`, switch to another window while an agent settles, and confirm a toast; if
  there is none, the documented escalation is `ubi:joshmedeski/wsl-notify-send` (ubi =
  mise-managed, so no Brewfile/apt parity work). `tmux set -g @pwt_notify 0` mutes
  the pushes meanwhile — the ⚑ flag and the C-w panel are independent of them.

## Deferred — judgment, not blocked

- [ ] **`git-prune-merged` is not wired into anything (2026-10-23).** It exists, is
  tested (dry-run default; `--apply` deletes merged locals; never gates on `[gone]`),
  and nothing calls it — so local branches whose PRs landed keep accumulating, which is
  the state that motivated it (dozens of `[gone]`/merged locals across the four lelapa
  repos). Next action: choose the rung (a `pwt`-adjacent habit, an `agents-update`-style
  alias, or a periodic prompt) and call it; keep the dry-run default.

- [ ] **`pwt <slug>` refuses inside a bare shell at a worktree root (2026-10-23,
  judgment).** Deliberate: a resurrect-restored pane and a shell merely `cd`'d into the
  worktree are indistinguishable, and respawning the pane `pwt` runs in would kill pwt —
  so it refuses loudly instead of opening a second window (`docs/PWT.md` §After a
  tmux-resurrect restore). Revisit if the `cd`-into-worktree flow proves common; the
  alternative is to open the window there and accept the duplicate on a restore.

- [ ] **MCP re-enable + credential rotation (2026-10-20).** `~/.pi/agent/mcp.json.disabled`
  holds a read-only Grafana + Linear config (Keychain-backed, write tools hidden,
  `exposure: codemode`) that is landed but switched off, with no record of why.
  Rotation of both credentials was never done (`pi-mcp-work-integration.md` follow-up
  #4) — do that first. Re-enable trigger: the first work-telemetry question that must
  be answered mid-session; then verify `pi mcp list` and one tool call per server in a
  throwaway session, and confirm the Keychain entries still resolve.

- [ ] **Prompt-slim watch (due ~2 weeks after c321cfb).** The always-on prompt was
  distilled (`APPEND_SYSTEM.md` 817 → 498 words, global `AGENTS.md` 201 → 138) and
  is now held by a 500-word budget in `check.sh`. `docs/PROMPT-EVAL.md` lists the
  signatures to re-check in ordinary sessions: a third attempt at one fix, an
  `oracle` brief carrying interpretation but no verbatim artifact, a `reviewer`
  spawn on a doc-only diff. The n=10 baseline favours the slim text; this is the
  check that it holds in real use.
- [ ] **Scaffolding review follow-ups (2026-10-20).** A read-only review of the agent
  scaffold (`~/.pi/agent` + this repo's `AGENTS.md`), second-opinioned by `oracle`.
  Landed from it: per-layer word budgets (500/185/1200, enforced in `check.sh`) and a
  `> **Status:**` line on every plan. Left, in value order:
  (a) spawn `worker` with `--no-context-files` — measured: every subagent pays ~1,346
  words of repo+global context, and `worker`'s contract already says "rely entirely on
  your briefing". Gate on a `pi-smoke` comparison, not on intuition.
  (b) a repeated-call watchdog in `hypa_shell` — the `loop` bug above is the prompt's
  stopping rules failing after two prompt-side fixes, so the next fix belongs in code;
  do it only after that bug's harness-vs-model split.
  (c) global `AGENTS.md` 178 → its recorded 138 target. A prompt edit, so it owes a
  `docs/PROMPT-EVAL.md` run on both sides; the 185 budget holds the line meanwhile.
  (d) trim the repo `Workflows` block (~60-100 words) — only when the 1,200 ratchet
  bites. The 11 words of headroom are deliberate, not a squeeze to relieve.
- [ ] **etckeeper config cleanup.** `base/git/.gitconfig-etckeeper` (disables
  GPG signing for `/etc` commits) is only useful on a native Linux host; none
  exists under `hosts/` today (mbpm3 = macOS, x13yg2/x1eg2 = WSL). Remove it
  and its stow include only if etckeeper is confirmed unused on any real
  machine; the `check.sh` tombstone for the includeIf stays meanwhile.
- [ ] **git-crypt URL-hint dedup.** The URL-hint regex is copy-pasted across
  alacritty configs; move it to a shared imported file and add a `check.sh`
  parity test.
- [ ] **Bitwarden Secrets Manager for provider keys — decided against (2026-10-19).**
  `BWS_ACCESS_TOKEN` has been removed from `secrets/env.fish` (it existed only to
  replicate CI/CD job runs locally) and is to be revoked after a canary week.
  Separately, the org's Secrets Manager is the deployment/external-secrets plane —
  its projects back ESO and the pipelines — so it is the wrong place for
  personal-shell material: wrong principal, wrong lifecycle, and a soft
  admin-controlled boundary. If provider keys ever move off git-crypt, the
  replacement is a personal store, not that org.

- [ ] **Revoke the retired ArgoCD admin API key (2026-10-19).** `ARGOCD_AUTH_TOKEN`
  was a never-expiring `admin:apiKey` exported into every process. It has been
  removed from `secrets/env.fish`, and the per-context token in the Argo CD CLI's
  own config is verified working without it. Revoke the key in Argo CD once a day
  or two has passed without anything breaking.

- [ ] **Work-laptop login friction (2026-10-19).** `work-login` / `work-status`
  (in the mbpm3 host package) re-auth idempotently. Remaining, in order of value:
  surface `work-status` in the tmux status bar so a lapsed session is visible
  before it bites; find out the org's IAM Identity Center session duration (the
  AWS refresh token re-mints hourly, but the sign-in session is what forces a
  browser, and it is org-configured); decide whether the ARO break-glass
  credential and the AKS kubeconfig contexts stay machine-local (they need a
  `$HOME` backup to survive a rebuild).
- [ ] **workmux trial — deferred; the status gap it named is now closed (2026-10-11,
  status 2026-10-20).** Higher-order pi session/agent management: git worktrees + tmux
  windows with per-agent status, prompt injection, merge/cleanup lifecycle, and a
  dashboard. Deferred because the acute bottleneck was solved without a new tool —
  `pi --session-id` per workstream, `pwt` for worktrees, and now the OSC 7501 tap +
  `C-w` panel + pushes for status (`docs/PWT.md`). What is still workmux-only: prompt
  injection, merge automation and the dashboard. Revisit only if manual bookkeeping
  costs >10 min/week, or if >=3 parallel mutating agents per repo become routine. If
  revisited:
  `mise use -g github:raine/workmux` (prebuilt binary — no rust toolchain, no
  Brewfile/check.sh parity work), mbpm3 first, window mode, and it must displace
  tmux-window-name plus its `libtmux` Python dependency to be net-negative surface. It
  must also be kept from writing through the stowed `settings.json` symlink (see
  docs/GOTCHAS.md §pi). Rejected outright: herdr, which replaces tmux rather than
  consolidating it.

- [ ] **`settings.json` write-back churn — pick a convention, then encode it.**
  pi rewrites `lastChangelogVersion` through the stowed symlink on every version
  change, so `base/pi/.pi/agent/settings.json` is dirty after any upgrade (and a
  model switch can ride along). There is no setting to suppress it — pi calls
  `setLastChangelogVersion` → `save()` when it shows a changelog
  (docs/GOTCHAS.md §pi). Today the rule is "revert before committing", applied by
  hand every time; the decision to make is whether to commit the value whenever it
  moves instead. Either way it should live in AGENTS.md so it stops being a
  per-commit judgement call.

## Out of scope (deliberate non-goals)

- `bootstrap.sh` stow conflict-resolution dance is battle-tested; don't
  refactor for style.
- tmux config, aerospace/komorebi parity, mise tiering, and the check.sh
  stow-integrity suite are the strong core; keep.