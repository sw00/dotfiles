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

- [ ] **pwt Tier 2 — ambient agent state per workstream (Tier 1 landed in
  f6b2e59).** Tier 1 gave `C-w` one panel (worktrees + live pi windows, verbs
  enter/ctrl-n/ctrl-d) and stopped a second pi from ever being spawned on one
  `--session-id` — which was not cosmetic: pi resumes that id's existing session
  and rewrites its JSONL from its own memory, so two writers clobber each other's
  turns with no lock to catch it. Tier 2 is the status signal: a flag in
  `window-status-format` for any workstream that wants a human, decaying when its
  window is focused.
  **Mechanism, corrected** — the workmux entry above calls this a gap because
  "pi emits working/blocked/done over OSC 7501, which tmux does not forward". True,
  but not a dead end: pi writes the OSC RAW (never DCS-wrapped, so `allow-passthrough`
  buys nothing), tmux consumes and discards it, and `pipe-pane` taps the bytes
  before that. Verified on a private server: 22 sequences captured from a session
  with NO client attached, and 17 from a non-current window. `PI_PROGRAM_STATUS=1`
  is required — it sets the same `programStatusSupported` flag the emitter is gated
  on, skipping the feature-detection query that tmux never answers. The status gap
  is therefore addressable without a new tool, which weakens workmux's remaining
  rationale: what is left of it is prompt injection and a merge/cleanup lifecycle,
  neither of which costs >10 min/week today.
  Decisions taken: `PI_PROGRAM_STATUS=1` goes in the tmux server env beside the
  existing PATH injection; the tap is attached by `pwt` to each pane it creates and
  adopted on `enter` for live pi rows, so coverage grows with use instead of needing
  a `pi` wrapper (which `subagent` would trip, since it spawns `pi` as a child and
  would re-tap the parent's pane) or an `after-new-window` poll hook.
  Two field-notes, both verified the hard way: **never** `pipe-pane -o` — a second
  call silently DETACHES the pipe rather than no-op'ing, so re-attach unconditionally;
  and the consumer must filter in C (`grep -a --line-buffered -o`) and always drain
  stdin, or the pane risks backpressure. Also note `pwt rm` now refuses while any
  pane sits inside the worktree, including a subdirectory.
  Tier 3 (push: `osascript` locally, PowerShell toast on WSL, ~5 min cooling-off per
  workstream) stays deferred until Tier 2 has been in use for a while: the payoff is
  unproven at one worktree and three sessions, and it is the piece carrying a
  platform asymmetry — click-to-jump needs `terminal-notifier` (brew) or nothing at
  all.

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