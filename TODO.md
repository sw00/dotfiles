<!-- Capture tier: TODO.md (analysis done, knock-off). See AGENTS.md §capture-tiers. -->

# TODO — dotfiles lean-up

Findings from a full review on 2026-06-26. The repo is well-architected
(three-layer `base → os → host` model, mise tiering, `check.sh` regression
suite). Changes below remove accumulated weight and fix a few real bugs.

## P0 — Bugs / correctness

- [x] **1. `check.sh` treesitter test fails on its own regex.**
  `check.sh:685` looks for `nvim-treesitter').install` but
  `treesitter.lua:13` is `require('nvim-treesitter.install').install {}`
  (no match). Fix the regex so CI is green on a correct repo.
- [x] **2. Stale test that can never fail.**
  `check.sh:544` asserts `conf.d/git.fish` (which doesn't exist) has no
  omf hooks → `check_not` on a missing file always passes. Remove it
  and any other tombstones testing absent files.
- [x] **3. `os/macos/gnupg/.gnupg/gpg-agent.conf` hardcodes `/Users/sett/...`.**
  gpg-agent doesn't expand `~`, but baking in the username is the wrong
  fix. Mirror the WSL pattern: have `bootstrap.sh` write
  `~/.gnupg/gpg-agent.conf` with `$HOME` expanded at install time; drop
  `os/macos/gnupg` from stow. Symmetric with WSL, removes the one
  machine-specific path in `os/`.
- [x] **4. `bootstrap.sh` and `check.sh` disagree on `base/bash`.**
  bootstrap never stows `base/bash` (`.profile` is Ubuntu boilerplate;
  PATH is handled by fish_add_path), but `check.sh:145` stows `bash` in
  the Linux stack. Drop `bash` from the check stow_layer so check
  verifies the layout bootstrap actually produces.
- [x] **5. Awesome WM is dead code.**
  `os/linux/awesome` has `rc.lua` (693 lines, ~95% stock default) +
  `theme.lua` with a hardcoded wallpaper path. `rc.lua` sources an
  `autorun.sh` that isn't in the repo. No host under `hosts/` uses native
  Linux desktop (only `x13yg2`=WSL, `mbpm3`=macOS). Delete the package.
  Resurrect from git history if native Linux ever returns. (~825 lines.)

## P1 — Lean (delete or merge cruft)

- [x] **6. `_archive/` should not exist in a dotfiles repo.** Git history
  is the archive. `git rm -r _archive` (keybindings.ahk,
  voicemeter-settings.xml, README).
- [x] **7. `os/macos/brew/brew-bundle-all.sh`** is a 2-line wrapper that
  duplicates `ensure_homebrew_bundle()` in bootstrap.sh. Delete; README
  already documents `brew bundle`.
- [x] **8. Alacritty `[colors]` block (~60 lines)** in `base.toml` is
  commented as "matches built-in defaults" — keep as a real source of
  truth for what *differs* from defaults by deleting the redundant block.

## Deferred (judgment — not in this pass)

These are sound but riskier; left for a follow-up PR.

- [x] [P2] Stale check.sh tombstones (~250 lines of `check_not` guard removed
  packages that can't recur). Strip forward-looking invariants only. — DONE in a7c953c.
- [x] [P2] Simplify secrets loading in `config.fish` to native `set -gx`
  lines in `secrets/env.fish` (drops the ~15-line bash parser). — DONE in a7c953c.
- [x] [P2] Consolidate the four `ip_addresses`/`wifi_status` scripts into a
  single `~/bin/tmux-status` that dispatches on `uname`/WSL. — DONE in a7c953c.
- [P2] Remove `base/git/.gitconfig-etckeeper` if etckeeper is unused.
- [P2] nvim: drop unmaintained `venv-selector.nvim`; migrate vim-test →
  neotest or remove.
- [P2] git-crypt: reduce the URL-hint regex copy-paste across alacritty
  configs to a shared imported file; add a check.sh parity test.
- [P2] Bitwarden Secrets Manager (BWS) for provider key provisioning.
  Current state: `BWS_ACCESS_TOKEN` is already in `secrets/env.fish`
  (git-crypt), but provider keys (`BRAVE_SEARCH_API_KEY`,
  `OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`) still
  live in that same file directly.

  Why: BWS gives per-host/project key partitioning without turning
  `secrets/` into a matrix of host-specific env files. Laptops share
  a global keyset; the agentbox (unattended, Telegram-bridged, lower
  trust) can pull a separate machine-scoped set with OpenRouter spend
  caps. Provider key rotation becomes a BWS dashboard edit instead of
  a git-crypt re-key + re-commit. `check.sh` and bootstrap stay simple
  because they only need to verify `BWS_ACCESS_TOKEN`.

  Path: add a `bws` CLI tool via mise (registry or aqua), add a
  fish `conf.d/bws-secrets.fish` that pulls keys at shell startup
  (`bws secret get <name> --output env`), keep `BWS_ACCESS_TOKEN`
  as the sole git-crypt secret.

  Risk: offline shell startup loses keys unless we cache or accept
  missing. Agentbox is the primary beneficiary; laptops can stay on
  direct keys if the offline risk matters.

  **Sub-item: rotate secrets during migration.** DONE (rotated out of band).
  The existing keys in `secrets/env.fish` were exposed in a prior agent session
  (tool output). `OPENROUTER_API_KEY`, `BRAVE_SEARCH_API_KEY`, and
  `ANTHROPIC_API_KEY` have been rotated. BWS migration remains future work.
- [P2] **OpenRouter ZDR lockdown.** The OR dashboard has per-request and
  global ZDR settings (ZDR-only routing + disable model training). Before
  relying on OR for sensitive work contexts, configure these. This is a
  one-time web-UI action, not a code change, but it gates the fallback
  mechanism's privacy guarantee.
- [x] [P2] **`check.sh` guard: summary model must not be free-tier.** OpenCode
  Go's free models (suffixed `-free`) train on data. Add a check that
  `base/pi/.pi/web-search.json` → `summaryModel` does not match `*-free`
  (and ideally does not contain any free-tier model from a known list).
  Also guard `settings.json` `enabledModels` for the same. — DONE in `fa7083c`.
- [P2] **Jan LLM-provider unification.** We unified web search (Brave MCP),
  but Jan still routes LLM queries through its own provider stack. If Jan
  is to become a first-class member of the unified AI stack, its LLM
  endpoint should point to the same primary providers (or through a shared
  gateway). Evaluate whether Jan's "Custom Endpoint" supports OpenCode Go
  directly, or whether it too should route through OpenRouter (with ZDR)
  for consistency with pi's fallback model.

## Out of scope (keep)

- `bootstrap.sh`'s stow conflict-resolution dance is ugly but
  battle-tested (asdf→mise migration comments). Don't refactor for style.
- tmux config, aerospace/komorebi parity, mise tiering, and the
  check.sh stow-integrity harness are the strong core. Keep.
- README is good.