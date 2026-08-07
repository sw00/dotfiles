# AGENTS.md — working notes for AI coding agents

## What this is

Personal dotfiles for macOS, WSL2, and native Linux. GNU stow symlinks
packages into `$HOME`; git-crypt encrypts `secrets/`; mise manages CLI tools
and runtimes. `bootstrap.sh` provisions a machine end-to-end; `check.sh` is
the regression suite (CI runs it on every push).

## Design principles (owner's — apply in this order)

1. One canonical config per application. Terminal experience (fish → tmux →
   alacritty) must be identical everywhere; design inside-out from the shell.
2. Platform-forced differences use the app's own override mechanism
   (alacritty `import`, tmux `if-shell`, fish `conf.d` guards).
3. Platform differences land in `os/<platform>/` first.
4. Host differences (`hosts/<hostname>/`) are the last resort: only genuine
   per-machine facts (hardware tuning, display DPI).

## Layout invariants (check.sh enforces these — keep them true)

- WSL host dirs contain bare files only (`.wslconfig`); never stow packages.
  WSL platform stow packages live in `os/wsl/`; Windows-side app config is
  pushed by `os/wsl/up.sh` (komorebi, VSCodium, winget list, fonts).
- Alacritty chain: `base/alacritty/base.toml` → platform config (shell, hint
  opener) → optional host config (font size only). `up.sh` copies
  host-else-platform-else-base to `%APPDATA%\Alacritty\`.
- gnupg is stowed per-OS, never from `base/` (pinentry differs per platform);
  `gpg-agent.conf` is written by bootstrap/up.sh with `$HOME` expanded.
- Dual-boot hosts keep one hostname on both OSes; safe because the `os/`
  layers own every platform-specific stow package.
- Hostname scheme: `<model><variant><generation>` (x13yg2, x1eg2, mbpm3).
  WSL hostname follows the Windows machine name; renaming = Rename-Computer
  on Windows + reboot, then rename the matching `hosts/` dir.
- Package placement is mise-first: `mise registry <tool>`, else `ubi:org/repo`
  for GitHub-release binaries. brew/apt/winget keep only bootstrap prereqs
  (stow, git-crypt, fish, mise itself), tools with no prebuilt binaries
  (tig, graphviz, mosh), platform integrations (pinentry, wslu, wireguard), and
  native libs (libpq, ffmpeg).
- Adding a system-package-only tool (not in mise/aqua/ubi) requires exactly
  three touch points: (1) `Brewfile-base` for macOS brew, (2) `ensure_system_tools()`
  `wanted` array in `bootstrap.sh` for Linux/WSL apt/dnf/pacman, (3) the parity
  loop in `check.sh` that asserts Brewfile-base ↔ ensure_system_tools consistency.
  Tools that don't run on Windows (mosh, native Linux/macOS-only tools) go to
  those two places only — no winget.txt entry.
- Cross-platform desktop apps are paired entries in `Brewfile-base` ↔
  `winget.txt`; check.sh's parity table enforces the mapping. Role-analogous
  platform apps (aerospace ↔ komorebi/whkd) are NOT parity pairs.

## Tiling window managers

AeroSpace (macOS) + Komorebi (Windows) share a common keybinding grammar.
Workspace scheme: 10 per monitor, 1-5 primary / 6-10 secondary.
See `docs/TILING.md` for full keybinding parity table and layout policy.

Key config paths:
- macOS: `hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml`
- Windows: `os/wsl/windows/komorebi/` (deployed by `up.sh`)

## Workflows

- Before committing: `bash check.sh` — commit only when green, and sanity-
  check the pass count (a harness bug once hid skipped tests behind a green
  summary). Commits are GPG-signed; the signing subkey must be imported.
- Adding a WSL host: `hosts/<hostname>/.wslconfig` is usually all you need;
  bootstrap discovers it by live hostname. Don't add stow packages there.
- Windows-side changes from WSL: write a `.ps1` to a Windows path, run
  elevated via `powershell.exe Start-Process -Verb RunAs -Wait` (one UAC
  prompt), log to a file, read results back via `/mnt/c`.
- Firmware/boot work: audit first (`bcdedit /enum firmware` + ESP listing +
  BitLocker status), suspend BitLocker protectors before changing boot
  entries, keep Windows Boot Manager first, verify with a re-dump.
- One-time machine migrations (removing/renaming installed software): dated
  `migrate_*()` functions in bootstrap.sh, every step guarded and idempotent,
  plus tombstone checks in check.sh so removed things can't creep back.
  Delete function + checks once all machines have migrated. Never delete
  user data in a migration (`brew uninstall` without `--zap`).
- bootstrap.sh sudo (Linux/WSL only; macOS never calls it): never
  `sudo bash bootstrap.sh` — stow/mise/fish would write root-owned files.
  `ensure_sudo()` runs `sudo -v` once, then a background `sudo -v -n` loop
  (every 60s, killed by the EXIT trap) keeps the 15-min ticket alive so it
  can't expire mid-run — bootstrap's privileged phase (`_ensure_wsl_conf`)
  installs `/etc/wsl.conf` while the ticket is alive, then up.sh's
  winget/fonts/VSCodium can outlast it. No-op if
  `sudo -n true` already succeeds. **Non-TTY (e.g. run from pi, no cached
  ticket): `sudo -v` aborts the whole script** — do the stow steps by hand (no
  sudo) and leave `ensure_system_tools`/`up.sh` for a real terminal.

## Capture tiers

Tier by how much analysis remains before the item is actionable:
`.pi/plans/` (host-local session scratch, gitignored, never commit) < `TODO.md` (analysis done, knock-off) < `ROADMAP.md` (needs deeper scoping). Record at the lowest tier that fits; escalate only when an item outgrows its tier.

## Reference material

**Gotchas** (things that went wrong, with fixes): `docs/GOTCHAS.md`
**Tiling WM keybinding table**: `docs/TILING.md`
**Pending work**: `TODO.md`, `ROADMAP.md`
