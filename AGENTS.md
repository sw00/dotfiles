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

## Tiling window managers (AeroSpace + Komorebi)

- **macOS** (mbpm3): AeroSpace — host config at
  `hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml`.
- **WSL/Windows** (x13yg2): Komorebi + whkd — *canonical* config at
  `os/wsl/windows/komorebi/` (not stowed; deployed by `os/wsl/up.sh` to
  `%USERPROFILE%\.config\`).

### Workspace scheme

10 workspaces per monitor (not 7). This matches the number row on a full
keyboard and gives each monitor a contiguous block (1-5 → primary, 6-10 →
secondary) for muscle memory across dual-monitor setups at home/work.

### Keybinding parity

AeroSpace and whkdrc share the same key grammar where komorebi supports it:

| Action | AeroSpace | whkdrc (Komorebi) |
|---|---|---|
| Focus | `alt-h/j/k/l` | `alt+h/j/k/l` |
| Move window | `alt-shift-h/j/k/l` | `alt+shift+h/j/k/l` |
| Workspace | `alt-1...0` | `alt+1...0` (0 → workspace 9) |
| Move to workspace | `alt-shift-1...0` | `alt+shift+1...0` |
| Resize ±50 | `alt-minus/equal` | `alt+-/= ` |
| Resize ±200 | `alt-shift-minus/equal` | `alt+shift+-/=` |
| Close window | `alt-q` | `alt+q` |
| Toggle float | `alt-f` | `alt+f` |
| Cycle layout | `alt-x` | `alt+x` |
| Back-and-forth | `alt-tab` | `alt+tab` |
| Focus monitor | `alt-ctrl-h/l` | `alt+ctrl+h/l` (h=prev, l=next) |
| Move to monitor | `alt-shift-ctrl-h/l` | `alt+shift+ctrl+h/l` (h=0, l=1) |

**Known asymmetry:** Komorebi lacks directional monitor navigation (only
cycle-monitor next/prev), so `alt+ctrl+h`=previous, `alt+ctrl+l`=next
(not true left/right). `alt+ctrl+j/k` were removed — they silently
duplicated h/l on a horizontal setup.

**alt-m differs:** AeroSpace = native macOS fullscreen (window leaves tiling);
Komorebi = toggle-monocle (maximised within tiling).

### Layout policy

All workspaces start as **BSP** (binary space partition). The OS default config
uses BSP everywhere; custom per-workspace layouts were removed for consistency
— use `alt-x` (cycle-layout) as the escape hatch for temporary changes.
Float rules are kept minimal: system dialogs, Bitwarden, Mullvad VPN,
Windows Terminal, Flameshot, and (on Windows only) Brave + Obsidian.

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
  can't expire mid-run — WSL `up.sh` prompts for `/etc/wsl.conf`, then
  winget/fonts/VSCodium can outlast it before `ensure_system_tools`. No-op if
  `sudo -n true` already succeeds. **Non-TTY (e.g. run from pi, no cached
  ticket): `sudo -v` aborts the whole script** — do the stow steps by hand (no
  sudo) and leave `ensure_system_tools`/`up.sh` for a real terminal.

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
- check.sh `check_has` patterns are line-based grep; multi-line assertions
  need `bash -c "... grep -A1 ... | grep -q ..."` instead.
- shellcheck runs at `-S warning`; info-level findings (e.g. SC2016 on
  intentional `bash -c '...$1...'` script bodies) are acceptable.
- Mosh: C++ with system deps (protobuf, utempter, openssl), no mise/ubi/Windows
  binary — system package manager everywhere; on WSL it's Linux-side, not Windows.
- stow lifecycle (per-file symlinks; always `--no-folding`):
  - Manual stow needs absolute dirs:
    `stow --restow --no-folding -d "$HOME/dotfiles/base" -t "$HOME" <pkg>`.
    A relative `-d base` resolves the target to the repo itself and writes
    broken `../base/...` symlinks; `stow_dir` in bootstrap.sh passes absolute
    paths — match it when stowing by hand.
  - Adding a file to an already-stowed package doesn't symlink it — re-stow
    (same command). Bit: pi couldn't load `infra-safety.ts` after
    `lib/infra-tables.ts` was added until the pi package was re-stowed.
  - Deleting a package leaves dangling symlinks stow can't unstow (the next
    bootstrap fails on the missing target). Remove by hand — or in a
    `migrate_*` function (see `migrate_app_trim`) — then re-stow. Bit: the
    komorebi host-config migration left `~/.config/komorebi/config.json`
    dangling after `hosts/x13yg2/komorebi/` was deleted upstream.
- pi config spans two roots under `base/pi/.pi/`: `agent/` (settings,
  extensions, agents, prompts, `AGENTS.md`, `APPEND_SYSTEM.md`) stows to
  `~/.pi/agent/`, and `web-search.json` (pi-web-access config) stows to
  `~/.pi/web-search.json` — a *sibling* of `agent/`, not inside it. Web search
  runs on Exa zero-config (no API key). See `base/pi/README.md`.
- Colima/Lima injects `Include .../.colima/ssh_config` into `~/.ssh/config` at
  install, dirtying the stowed base config. Pre-empted: base already includes
  `~/.colima/ssh_config` (harmless when absent on non-colima hosts).
- `brew bundle` (host Brewfile) can hit the 600s timeout when several large
  casks download at once (colima image, pycharm, readest, signal, ffmpeg).
  Idempotent — just re-run.
- Docker Desktop uninstall (`brew uninstall --cask docker-desktop`) leaves
  privileged helpers behind: its sudo prompts fail silently in a
  non-interactive script. No user data lost (never `--zap`), but a manual
  `sudo rm -f /Library/PrivilegedHelperTools/com.docker.socket` is needed.
- `mas`-managed casks (WhatsApp, Pixelmator) need an active Mac App Store
  session — `brew bundle` fails for them otherwise.
- Pre-existing config files written by other tools (e.g. `**/.claude/settings.local.json`
  in `~/.config/git/ignore` from Claude/Cline) create stow conflicts caught by
  `_stow_preflight`.  Merge the content into the stowed version, remove the
  blocking plain file, then re-stow.
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
  `git checkout` any unintended default-model/provider drift (default is
  `deepseek-v4-pro`; roster is deliberately minimal — 6 models, each with a
  distinct role).
- pi safety has two independent axes: session posture (change/check/chat) vs.
  per-domain write-gate (locked/armed, e.g. infra) — two-key; the infra gate
  opens only when both allow. Never conflate the vocabularies. Details:
  `base/pi/README.md`.
- Subagents (oracle, reviewer, ...) load infra-safety locked with
  `hasUI=false` → infra mutations hard-blocked regardless of prompt; general
  bash stays unguarded (oracle needs it for diagnosis). Details:
  `base/pi/README.md`.
- pi infra-safety false-positives on commit messages: its scanner
  (`findInvocations` in `lib/classify.ts`) reads the whole bash command string
  quote-unaware, so `git commit -m "...terraform..."` parses as a terraform
  invocation → "unrecognised verb, blocked" while the gate is locked (every
  context, incl. subagents). Fix: write the message to a file and
  `git commit -F <file>` — heredocs do NOT help (the body is scanned too).
- nvim-treesitter v1.0 changed parser installation API: `ensure_installed`
  was renamed to `install` on the top-level module (`require('nvim-treesitter').install { ... }`
  not `require('nvim-treesitter.install').ensure_installed(...)`), and takes
  a table `{ ... }` argument, not varargs.
- Migrating from packer.nvim to lazy.nvim: the old `plugin/packer_compiled.lua`
  file and `~/.local/share/nvim/site/pack/packer/` directory persist after
  switching package managers.  The compiled loader still runs on every startup
  and adds old plugins to the runtimepath, causing circular-dependency errors
  (especially nvim-tree + fidget integration) that look like lazy.nvim config
  bugs.  Both must be manually removed when switching.
- `checkhealth vim.provider` hangs on WSL when `xsel` is installed but no X
  server is running.  The clipboard probe (built into Neovim, runs before user
  config) blocks indefinitely.  The system-level fix is `apt remove xsel` since
  `wsl-clipboard.lua` provides proper clipboard via `clip.exe` / powershell.
  The hang only affects health checks, not actual clipboard use.
  `git checkout` any unintended default-model/provider drift (default is
  `deepseek-v4-pro`; roster is deliberately minimal — 6 models, each with a
  distinct role).
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
- VSCodium `--install-extension` emits harmless `DEP0169` warnings from its
  bundled Electron/Node (not mise/system node). Extensions install fine.
  Filter them in bootstrap.sh alongside `"already installed"` to keep the
  bootstrap log clean.
- Electron apps (Discord, VSCodium) bundle their own Node.js — mise/system
  Node is never involved in their issues. Don't chase Node versions for
  Electron app problems.
- Discord brew cask can install metadata without moving the `.app` to
  `/Applications`, leaving a dangling Caskroom symlink. Fix: `brew reinstall
  --cask discord`.
- Discord auto-updater (Squirrel/ShipIt) caches old versions in
  `~/Library/Application Support/discord/app-*` and conflicts with a brew
  reinstall, producing `InconsistentInstallerState`. Fix: quit Discord,
  remove old `app-*` dirs and updater state files (`ShipIt_request.json`,
  `installer.db`), then relaunch. The app will auto-update itself again.

## Known pending work

- x1eg2: Pop!_OS dual-boot install pending — set hostname `x1eg2`; see
  README "Adding a new host → Dual-boot machines".
- TODO.md tracks older review items; P2 "deferred" list is still open.
- mbpm3: app-trim migration ran (2026-07 lean pass).  `migrate_app_trim` kept
  for x1eg2 if/when it boots macOS; delete the function, its call, and the
  tombstone checks in check.sh once all macs have run it.
