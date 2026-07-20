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
- Never run bootstrap.sh as root (`sudo bash bootstrap.sh`) — stow, mise, and
  fish config would write wrong ownership. Instead, `ensure_sudo()` at the top
  of the Linux/WSL path calls `sudo -v` once to prompt for your password, then
  keeps the ticket alive with a background `sudo -v -n` loop (refreshed every
  60s, reaps itself if the ticket can't be refreshed). The EXIT trap kills the
  background loop when the script finishes. If `sudo -n true` already succeeds
  (cached ticket or passwordless sudo), `ensure_sudo` is a no-op.

## Gotchas (learnt the hard way)

- Headless nvim checks: always `nvim -u NONE --headless ... -c 'qa!'` — the
  user's init.lua may be broken/Nix-managed and block on a prompt; plain
  `qa` hangs on modified buffers.
- stow prints "BUG in find_stowed_path" for symlinks it can't own (Nix
  store, /mnt/c). Known noise; `bootstrap.sh` already filters it.
- WSL interop can vanish mid-session (binfmt_misc/WSLInterop disappears).
  Re-register with:
  `sudo bash -c 'echo ":WSLInterop:M::MZ::/init:PF" > /proc/sys/fs/binfmt_misc/register'`
- Linux/WSL has no system ssh-agent: `base/fish/.../conf.d/ssh-agent.fish`
  runs one shared agent on `~/.ssh/agent.sock` (adopts platform sockets on
  macOS). Extend that file rather than adding another mechanism.
- git credential.helper values with spaces need `!\"...\"` quoting
  (`os/wsl/git/.gitconfig-wsl`); canonical remotes are SSH anyway.
- bash `${var#...}` tolerates no spaces around the operator.
- Deleting a stow package leaves stale symlinks in `$HOME` — stow cannot
  unstow what no longer exists. Clean up in a `migrate_*` function
  (see `migrate_app_trim`).
- check.sh `check_has` patterns are line-based grep; multi-line assertions
  need `bash -c "... grep -A1 ... | grep -q ..."` instead.
- shellcheck runs at `-S warning`; info-level findings (e.g. SC2016 on
  intentional `bash -c '...$1...'` script bodies) are acceptable.
- Mosh is a C++ tool with system deps (protobuf, utempter, openssl) — no mise
  registry, no ubi backend, no Windows native binary. Installed via system
  package manager on all platforms. On WSL it lives in the Linux subsystem,
  not the Windows side.
- Sudo session expiry is a recurring bootstrap.sh hazard: WSL `up.sh` prompts
  for sudo to write `/etc/wsl.conf`, but by the time `ensure_system_tools()`
  runs (winget installs, font downloads, VSCodium setup can take minutes),
  the 15-minute sudo ticket may have expired. `ensure_sudo()` at the top of
  the Linux/WSL path prevents this by keeping the ticket alive for the full
  duration.
- Manual stow needs absolute dirs:
  `stow -d "$HOME/dotfiles/base" -t "$HOME" -R <pkg>`. A relative `-d base`
  from the repo root resolves the target to the repo itself and writes broken
  `../base/...` symlinks. `bootstrap.sh`'s `stow_dir` already passes absolute
  paths; match it when stowing by hand.
- pi config spans two roots under `base/pi/.pi/`: `agent/` (settings,
  extensions, agents, prompts, `AGENTS.md`, `APPEND_SYSTEM.md`) stows to
  `~/.pi/agent/`, and `web-search.json` (pi-web-access config) stows to
  `~/.pi/web-search.json` — a *sibling* of `agent/`, not inside it. Web search
  runs on Exa zero-config (no API key). See `base/pi/README.md`.
- pi TS extensions: relative imports need explicit `.ts` extensions
  (`./classify.ts`) so `node --experimental-strip-types --test` runs the unit
  tests; jiti (pi's loader) accepts either form. Verify an extension parses
  with `pi -p --no-session "Reply OK"` — load errors print at startup.
- pi agent discovery: the `subagent` tool's `description:` frontmatter is not
  shown to the model except on an error path; the model learns which agents
  exist only from `APPEND_SYSTEM.md`, which is always in the system prompt.
  Keep that file lean and keep its agent roster in sync with `agent/agents/`.
- pi writes runtime state (selected model, `lastChangelogVersion`) back through
  the stowed `settings.json` symlink, so a plain `pi` run can dirty
  `base/pi/.pi/agent/settings.json` — e.g. flipping `defaultModel` to whatever
  was last picked. Before committing pi changes, `git diff` it and
  `git checkout` any unintended default-model/provider drift (Flash-first keeps
  `deepseek-v4-flash`).
- pi safety model has two independent state axes: **session posture**
  (change/check/chat via mode commands) and **domain write-gates**
  (locked/armed per domain like infra). A guard can be armed while modes is
  chat; modes can be change while a guard is locked. The infra write gate only
  opens when both axes allow it — two-key safety. Never conflate the two
  vocabularies in edits or docs.
- Subagent processes spawned by pi (oracle, reviewer, ...) load infra-safety
  independently, default to locked, and run without an interactive UI —
  live-infra mutations are hard-blocked regardless of the agent prompt.
  General bash (test runners, builds) stays unguarded because oracle needs
  them for diagnosis. This asymmetry is intentional: the tool gate covers
  the highest-risk domain; the agent prompt covers the rest.

## Known pending work

- x13yg2 (when next touched): `git pull && bash bootstrap.sh` self-heals
  the alacritty symlink to `os/wsl`; remove the dangling
  `~/.config/komorebi/config.json` symlink by hand.
- x1eg2: Pop!_OS dual-boot install pending — set hostname `x1eg2`; see
  README "Adding a new host → Dual-boot machines".
- TODO.md tracks older review items; P2 "deferred" list is still open.
- mbpm3 (when next bootstrapped): `migrate_app_trim` (2026-07) uninstalls
  the trimmed casks and sets up colima. Once every mac has run it, delete
  the function, its call, and the tombstone checks in check.sh.
