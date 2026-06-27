# dotfiles

Personal config files for macOS, WSL2, and Linux. Managed with
[GNU stow](https://www.gnu.org/software/stow/) and
[git-crypt](https://github.com/AGWA/git-crypt).

## Layout

Configs are applied in three layers, from most general to most specific:

```
base/           → applied on every platform
os/
  linux/        → native Linux desktop (bin scripts, alacritty)
  macos/        → macOS (Brewfiles, pinentry-mac, gpg-agent)
  wsl/          → WSL2 Linux side (gitconfig, up.sh)
    windows/    → content pushed to Windows FS (wsl.conf, VSCodium, winget list)
hosts/
  mbpm3/        → MacBook Pro M3 (alacritty, Brewfile-host, key remap agents)
  x13yg2/       → ThinkPad X13 running WSL2 (wslconfig, alacritty)
secrets/        → git-crypt encrypted (SSH keys, env.sh)
```

`base/` packages: `bash`, `fish`, `git`, `gnupg`, `nvim`, `ssh`, `tmux`,
`alacritty`, `mise`.

Stow maps each package's directory tree into `~` with symlinks. For example,
`base/nvim/.config/nvim/init.lua` → `~/.config/nvim/init.lua`.

## Package managers

Three tiers, each managed by the appropriate tool:

| Level | Scope | macOS | Linux / WSL2 | Windows |
|---|---|---|---|---|
| 1 — OS packages | Desktop apps, system libs, platform integrations | Homebrew (`brew bundle`) | apt | winget (via `up.sh`) |
| 2 — CLI tools | neovim, tmux, fzf, kubectl, … | mise | mise | mise |
| 3 — Language runtimes | Node, Python, … | mise | mise | mise |

**mise** (`base/mise/.config/mise/config.toml`) is the single source of truth
for levels 2 and 3 across all platforms. See that file for the full tool list.

Tools not in the [aqua registry](https://aquaproj.github.io/aqua-registry/)
(`lf`, `tig`) are installed by the OS package manager instead.

## Bootstrap

> **Prerequisite — all platforms:** the repo uses git-crypt. Clone first,
> then unlock before running `bootstrap.sh`, otherwise SSH and GPG configs
> will be skipped (encrypted blobs cannot be stowed safely).
>
> ```bash
> git clone git@github.com:sw00/dotfiles.git ~/dotfiles
> cd ~/dotfiles
> git-crypt unlock          # requires your GPG key to be available
> bash bootstrap.sh
> ```

### macOS

```bash
git clone git@github.com:sw00/dotfiles.git ~/dotfiles
cd ~/dotfiles
git-crypt unlock
bash bootstrap.sh
```

`bootstrap.sh` on macOS:
1. Installs Xcode CLT and Homebrew if absent
2. Stows all config layers
3. Runs `brew bundle` for `~/.Brewfile-base` and `~/.Brewfile-host`
4. Installs Fisher and fish plugins
5. Installs mise tools and language runtimes

### Windows (WSL2)

Open a WSL terminal and run:

```bash
git clone git@github.com:sw00/dotfiles.git ~/dotfiles
cd ~/dotfiles
git-crypt unlock
bash bootstrap.sh
```

`bootstrap.sh` on WSL additionally calls `os/wsl/up.sh`, which:
- Installs Windows apps from `os/wsl/windows/winget.txt` via `winget`
- Installs and registers CaskaydiaCove Nerd Font (per-user, no admin needed)
- Copies Alacritty config (`base.toml` + host override) to `%APPDATA%\Alacritty\`
- Installs VSCodium settings and extensions
- Copies `.wslconfig` (host-specific hardware tuning) to `%USERPROFILE%\`

`up.sh` is idempotent and can be re-run any time to re-apply Windows-side config.

**WSL is configured with systemd** (`os/wsl/windows/wsl.conf`). After first
run, restart WSL to apply: `wsl.exe --shutdown`.

### Linux

```bash
git clone git@github.com:sw00/dotfiles.git ~/dotfiles
cd ~/dotfiles
git-crypt unlock
bash bootstrap.sh
```

`bootstrap.sh` on Linux installs system tools via apt, then mise, then
CaskaydiaCove Nerd Font to `~/.local/share/fonts/`.

## Secrets and git-crypt

The following are encrypted at rest and only readable after `git-crypt unlock`:

| Path | Contents |
|---|---|
| `secrets/env.sh` | API tokens, sourced by `config.fish` at shell startup |
| `secrets/ssh/` | Private SSH keys |
| `base/ssh/.ssh/config.d/` | SSH host configs referencing the private keys |

**Unlock** requires your GPG private key. On a new machine, import it first:

```bash
gpg --import <exported-secret-key.asc>
git-crypt unlock
```

**Add a new collaborator** (run once on an unlocked clone):

```bash
git-crypt add-gpg-user <collaborator-gpg-key-id>
git push
```

## Adding a new host

1. Create the host directory: `hosts/<hostname>/`
2. Add an Alacritty override (font size, shell args):
   ```
   hosts/<hostname>/alacritty/.config/alacritty/alacritty.toml
   ```
   It must start with `import = ["~/.config/alacritty/base.toml"]`.
3. For WSL machines, add `.wslconfig` with memory/CPU tuning:
   ```
   hosts/<hostname>/.wslconfig
   ```
   `up.sh` reads this automatically by hostname at runtime.
4. `bootstrap.sh` picks up `hosts/<hostname>/` automatically — no changes
   to the script needed.

The hostname is derived with `hostname -s | tr '[:upper:]' '[:lower:]'`.

## Local overrides (not tracked)

Some machine-specific settings don't belong in the repo:

| File | Purpose |
|---|---|
| `~/.config/tmux/tmux.local.conf` | Font size, status-bar tweaks per monitor |
| `~/.ssh/config.d/wtc.conf` | Work SSH hosts (referenced in `~/.ssh/config`) |

## Testing

```bash
bash check.sh
```

Tests cover shell script syntax, stow integrity across all platform stacks,
config parsability (tmux, git, fish), and structural invariants.
Requires `stow` and `fish`. `shellcheck` (installed via mise) enables
extended linting.

CI runs on every push via `.github/workflows/check.yml`.
