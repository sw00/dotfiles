# Gotchas (learnt the hard way)

Reference material — load when debugging a specific issue. Not always-loaded context.

## Neovim

- Headless nvim checks: always `nvim -u NONE --headless ... -c 'qa!'` — the user's init.lua may be broken/Nix-managed and block on a prompt; plain `qa` hangs on modified buffers.
- nvim-treesitter v1.0 (`branch = main`, entrypoint `lua/nvim-treesitter/init.lua`): the top-level module exposes ONLY `setup()` and `indentexpr()`. Use `require('nvim-treesitter').setup { ensure_install = { ... } }` — note `ensure_install` (singular, no `ed`). `config.setup` runs the install asynchronously. The old `highlight = { enable = true }` module is gone; use `vim.treesitter.start` in a FileType autocmd instead. Gotcha: the working tree can lag lazy-lock.json after an update — HEAD on the old master lineage while the lockfile pins v1.0 main. Fix: `:Lazy restore`.
- Migrating from packer.nvim to lazy.nvim: the old `plugin/packer_compiled.lua` file and `~/.local/share/nvim/site/pack/packer/` directory persist after switching package managers. The compiled loader still runs on every startup and adds old plugins to the runtimepath, causing circular-dependency errors.
- `checkhealth vim.provider` hangs on WSL when `xsel` is installed but no X server is running. Fix: `apt remove xsel` (wsl-clipboard.lua provides clipboard via clip.exe).

## stow lifecycle

- Always use `--no-folding`. Manual stow needs absolute dirs: `stow --restow --no-folding -d "$HOME/dotfiles/base" -t "$HOME" <pkg>`.
- Adding a file to an already-stowed package doesn't symlink it — re-stow (same command).
- Deleting a package leaves dangling symlinks stow can't unstow. Remove by hand first, then re-stow.
- Pre-existing config files from other tools (e.g. `**/.claude/settings.local.json`) create stow conflicts. Merge, remove blocking file, re-stow.
- stow prints "BUG in find_stowed_path" for symlinks it can't own (Nix store, /mnt/c). Known noise; bootstrap.sh filters it.

## git-crypt / GPG

- git-crypt GPG subkey may expire. Fallback: `git-crypt unlock ~/homelab-git-crypt-key`.
- `gpg --export-secret-subkeys` copies the ENCRYPTED stub — no passphrase prompt at export time. The prompt fires on first signing USE on the receiving machine.
- `gpg-agent.conf`'s `pinentry-program` line parser truncates at the first space. Leave it unset on Windows (Gpg4win defaults to its GUI pinentry-qt).
- Gpg4win installs to `C:\Program Files\GnuPG\bin\`, NOT `Program Files (x86)`.
- Gpg4win's `--list-secret-keys` shows a `[keyboxd]` keyring; that's normal.

## WSL / Windows

- WSL interop can vanish mid-session (binfmt_misc/WSLInterop disappears). Re-register: `sudo bash -c 'echo ":WSLInterop:M::MZ::/init:PF" > /proc/sys/fs/binfmt_misc/register'`
- Windows-side `git.exe` spawned from WSL cannot read message files in WSL `/tmp` (separate filesystem). Use `/mnt/c/Users/<u>/AppData/Local/Temp/` instead.
- git credential.helper values with spaces need `!\"...\"` quoting (`os/wsl/git/.gitconfig-wsl`); canonical remotes are SSH anyway.

## pi

- pi config spans two roots under `base/pi/.pi/`: `agent/` (settings, extensions, agents, prompts) stows to `~/.pi/agent/`, and `web-search.json` stows to `~/.pi/web-search.json` — a sibling, not inside it.
- `pi-hypa` replace mode disables the native `bash`/`read`/`grep`/`find`/`ls` tools.
  Safety extensions (`infra-safety`, `/check` mode) intercept `hypa_shell` directly
  and classify the raw command; no wrapper-unwrapping is needed.
- `pi-web-access` is not redundant — Pi core has no native `web_search`,
  `fetch_content`, `source_check`, or `get_search_content` tools.
- pi writes runtime state (selected model, `lastChangelogVersion`) back through the stowed `settings.json` symlink. Before committing pi changes: `git diff` and `git checkout` any unintended default-model drift (default is `deepseek-v4-pro`).
- pi safety has two independent axes: session posture (change/check/chat) vs. per-domain write-gate (locked/armed). Never conflate. See `base/pi/README.md`.
- Subagents load infra-safety locked with `hasUI=false` → infra mutations hard-blocked. General bash stays unguarded (oracle needs it). Intentional asymmetry.
- pi infra-safety false-positives on commit messages: `git commit -m "...terraform..."` parses as a terraform invocation → blocked. Fix: `git commit -F <file>`.
- pi agent discovery: the `subagent` tool's `description:` frontmatter is not shown to the model except on an error path. The model learns agents from `APPEND_SYSTEM.md` only.
- pi TS extensions: relative imports need explicit `.ts` extensions (`./classify.ts`) for node --experimental-strip-types.
- **Shared core must be host-agnostic.** `base/pi/.pi/agent/` is copied verbatim to every deployment. No `telegram`, `agentbox`, `tg-*`, `pi-telegram`, `[telegram]`. Those live in homelab overlay files. `check.sh` enforces this.

## macOS

- `bootstrap.sh` must not reload Homebrew-managed launch agents (`homebrew.mxcl.*`).
  `load_macos_launch_agents()` only reloads plists that are symlinks into the
  dotfiles repo (`$DOTFILES`). Homebrew agents are skipped to avoid transient
  `launchctl bootstrap` failures (e.g. colima mid-start) aborting the whole run.
- Colima/Lima injects `Include .../.colima/ssh_config` into `~/.ssh/config`. Pre-empted: base already includes `~/.colima/ssh_config` (harmless when absent).
- `brew bundle` (host Brewfile) can hit 600s timeout when several large casks download. Idempotent — just re-run.
- Docker Desktop uninstall leaves privileged helpers behind. Manual `sudo rm -f /Library/PrivilegedHelperTools/com.docker.socket`.
- `mas`-managed casks need an active Mac App Store session — `brew bundle` fails otherwise.
- Discord brew cask can leave a dangling Caskroom symlink. Fix: `brew reinstall --cask discord`.
- Discord auto-updater caches old versions in `~/Library/Application Support/discord/app-*`. Fix: quit Discord, remove old dirs + updater state files, relaunch.

## General

- bash `${var#...}` tolerates no spaces around the operator.
- `check.sh` `check_has` patterns are line-based grep. Multi-line assertions need `bash -c "... grep -A1 ... | grep -q ..."`. `check_not` patterns must be `^-anchored`.
- Mosh needs system packages (protobuf, utempter, openssl) — no mise/ubi binary.
- Linux/WSL has no system ssh-agent: `base/fish/.../conf.d/ssh-agent.fish` runs a shared agent on `~/.ssh/agent.sock`. Extend that file, don't add another.
- shellcheck runs at `-S warning`; info-level findings are acceptable.
- `gh repo delete` needs the `delete_repo` scope. `gh auth refresh -h github.com -s delete_repo` first.
- VSCodium `--install-extension` emits harmless `DEP0169` warnings. Extensions install fine.
- Electron apps bundle their own Node.js — mise/system Node is never involved in their issues.
