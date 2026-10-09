<!-- Capture tier: TODO.md (analysis done, knock-off). See AGENTS.md §capture-tiers. -->

# TODO — open/deferred work

This file tracks only genuine open or deferred work; completed fixes were
removed — full implementation history lives in git. Shared-core behavior
(`base/`) is validated by `./check.sh`; run it before committing.

## Open — active bug

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
- [ ] **nvim plugin cleanup.** Drop unmaintained `venv-selector.nvim`; migrate
  `vim-test` → neotest or remove (retirement note already in `ide.lua`).
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

## Out of scope (deliberate non-goals)

- `bootstrap.sh` stow conflict-resolution dance is battle-tested; don't
  refactor for style.
- tmux config, aerospace/komorebi parity, mise tiering, and the check.sh
  stow-integrity suite are the strong core; keep.