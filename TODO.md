<!-- Capture tier: TODO.md (analysis done, knock-off). See AGENTS.md §capture-tiers. -->

# TODO — open/deferred work

This file tracks only genuine open or deferred work; completed fixes were
removed — full implementation history lives in git. Shared-core behavior
(`base/`) is validated by `./check.sh`; run it before committing.

## Open — active bug

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

- [ ] **Prompt-slim watch (due ~2 weeks after c321cfb).** The always-on prompt was
  distilled (`APPEND_SYSTEM.md` 817 → 498 words, global `AGENTS.md` 201 → 138) and
  is now held by a 500-word budget in `check.sh`. `docs/PROMPT-EVAL.md` lists the
  signatures to re-check in ordinary sessions: a third attempt at one fix, an
  `oracle` brief carrying interpretation but no verbatim artifact, a `reviewer`
  spawn on a doc-only diff. The n=10 baseline favours the slim text; this is the
  check that it holds in real use.
- [ ] **etckeeper config cleanup.** `base/git/.gitconfig-etckeeper` (disables
  GPG signing for `/etc` commits) is only useful on a native Linux host; none
  exists under `hosts/` today (mbpm3 = macOS, x13yg2/x1eg2 = WSL). Remove it
  and its stow include only if etckeeper is confirmed unused on any real
  machine; the `check.sh` tombstone for the includeIf stays meanwhile.
- [ ] **git-crypt URL-hint dedup.** The URL-hint regex is copy-pasted across
  alacritty configs; move it to a shared imported file and add a `check.sh`
  parity test.
- [ ] **Bitwarden Secrets Manager (BWS) for provider keys — future/optional.**
  `BWS_ACCESS_TOKEN` is already in `secrets/env.fish` (git-crypt), but provider
  keys still live there directly. BWS would give per-host/project key
  partitioning and dashboard-driven rotation instead of git-crypt re-key, with
  `check.sh` verifying only `BWS_ACCESS_TOKEN`. Path: add `bws` via
  mise/aqua, pull keys through a fish `conf.d` hook at shell startup. Risk:
  offline shell startup loses keys unless cached; machines can stay on direct
  keys if that risk matters. Direct keys were rotated out-of-band after a prior
  exposure; migration not started — needs an owner decision on the offline
  trade-off.
- [ ] **workmux trial — deferred (2026-10-11).** Higher-order pi session/agent
  management: git worktrees + tmux windows with per-agent status, prompt injection,
  merge/cleanup lifecycle, and a dashboard. Deferred because the acute bottleneck was
  solved without a new tool — `pi --session-id` gives per-workstream session handles
  and the `pwt` fish function covers parallel mutating work — so the only remaining
  gap is agent *status* inside tmux (pi emits working/blocked/done over OSC 7501, which
  tmux does not forward). Revisit only if manual bookkeeping costs >10 min/week, or if
  >=3 parallel mutating agents per repo become routine. If revisited:
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