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

- [P2] Stale check.sh tombstones (~250 lines of `check_not` guard removed
  packages that can't recur). Strip forward-looking invariants only.
- [P2] Simplify secrets loading in `config.fish` to native `set -gx`
  lines in `secrets/env.fish` (drops the ~15-line bash parser).
- [P2] Consolidate the four `ip_addresses`/`wifi_status` scripts into a
  single `~/bin/tmux-status` that dispatches on `uname`/WSL.
- [P2] Remove `base/git/.gitconfig-etckeeper` if etckeeper is unused.
- [P2] nvim: drop unmaintained `venv-selector.nvim`; migrate vim-test →
  neotest or remove.
- [P2] git-crypt: reduce the URL-hint regex copy-paste across alacritty
  configs to a shared imported file; add a check.sh parity test.

## Out of scope (keep)

- `bootstrap.sh`'s stow conflict-resolution dance is ugly but
  battle-tested (asdf→mise migration comments). Don't refactor for style.
- tmux config, aerospace/komorebi parity, mise tiering, and the
  check.sh stow-integrity harness are the strong core. Keep.
- README is good.