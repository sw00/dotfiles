#!/usr/bin/env bash
# Bootstrap dotfiles across macOS, WSL2, and Linux.
# Idempotent: safe to re-run. Installs prerequisites if missing,
# then symlinks configs via GNU stow.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

detect_platform() {
    case "$(uname -s)" in
        Darwin) echo macos ;;
        Linux)
            if [[ -e /proc/sys/fs/binfmt_misc/WSLInterop ]] || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
                echo wsl
            else
                echo linux
            fi
            ;;
        *) err "unsupported OS: $(uname -s)" ;;
    esac
}

normalize_hostname() {
    local h
    h="$(hostname)"
    h="${h%%.*}"
    printf '%s' "$h" | tr '[:upper:]' '[:lower:]'
}

ensure_macos_prereqs() {
    if ! xcode-select -p >/dev/null 2>&1; then
        log "installing Xcode Command Line Tools (interactive prompt)"
        xcode-select --install || true
        warn "rerun bootstrap.sh once CLT install completes"
        exit 0
    fi
    if ! command -v brew >/dev/null 2>&1; then
        log "installing Homebrew"
        NONINTERACTIVE=1 /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if   [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew    ]]; then eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
    for pkg in stow git-crypt; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            log "brew install $pkg"
            brew install "$pkg"
        fi
    done
}

# Mapping from command name → package name where they differ per manager.
# Key is the command; value is the installable package name.
_pkg_name() {
    local cmd="$1" mgr="$2"
    case "$mgr:$cmd" in
        apt:wslview)  echo wslu ;;    # wslu provides wslview on Ubuntu
        apt:git-lfs)  echo git-lfs ;;
        *)            echo "$cmd" ;;
    esac
}

_install_pkgs() {
    local mgr="$1"; shift
    local cmds=("$@")
    local pkg_names=()
    for cmd in "${cmds[@]}"; do
        pkg_names+=("$(_pkg_name "$cmd" "$mgr")")
    done
    case "$mgr" in
        apt)    sudo apt-get update -qq && sudo apt-get install -y "${pkg_names[@]}" ;;
        dnf)    sudo dnf install -y "${pkg_names[@]}" ;;
        pacman) sudo pacman -S --noconfirm "${pkg_names[@]}" ;;
        nix)    nix-env -iA "${pkg_names[@]/#/nixpkgs.}" ;;
    esac
}

_detect_pkg_mgr() {
    if   command -v apt-get >/dev/null 2>&1; then echo apt
    elif command -v dnf     >/dev/null 2>&1; then echo dnf
    elif command -v pacman  >/dev/null 2>&1; then echo pacman
    elif command -v nix-env >/dev/null 2>&1; then echo nix
    else echo ""
    fi
}

ensure_linux_prereqs() {
    local mgr; mgr="$(_detect_pkg_mgr)"
    [[ -n "$mgr" ]] || err "no known package manager found"

    local missing=()
    for cmd in stow git-crypt; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "installing prerequisites via $mgr: ${missing[*]}"
        _install_pkgs "$mgr" "${missing[@]}"
    fi
}

ensure_system_tools() {
    # Installs only what mise cannot provide:
    #   fish    — login shell; must exist before mise activates
    #   git-lfs — git integration, not a standalone binary tool
    #   lf, tig — not in the aqua/mise registry; must come from system packages
    #   xclip / wslview — WSL platform integrations (no aqua equivalent)
    # Everything else (tmux, neovim, fzf, devops tools, ...) is in mise.
    local mgr; mgr="$(_detect_pkg_mgr)"
    [[ -n "$mgr" ]] || { warn "no package manager — skipping system tool installation"; return 0; }

    local wanted=(fish git-lfs lf tig)
    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        wanted+=(wslview xclip)  # wslview is the binary from the wslu package
    fi

    local missing=()
    for cmd in "${wanted[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    [[ ${#missing[@]} -eq 0 ]] && { log "system tools already installed"; return 0; }

    log "installing system tools via $mgr: ${missing[*]}"
    _install_pkgs "$mgr" "${missing[@]}"
}

ensure_fisher() {
    # Install Fisher and plugins. Runs once; fish_plugins file is the manifest.
    if ! command -v fish >/dev/null 2>&1; then
        warn "fish not installed — skipping Fisher setup"
        return 0
    fi

    local plugins="$HOME/.config/fish/fish_plugins"

    if fish -c 'functions -q fisher' 2>/dev/null; then
        log "fisher already installed"
    else
        log "installing fisher"
        fish -c '
            curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/HEAD/functions/fisher.fish \
                | source && fisher install jorgebucaran/fisher
        ' 2>&1
    fi

    if [[ -f "$plugins" ]]; then
        log "installing fish plugins"
        fish -c 'fisher update' 2>&1
    fi
}

ensure_nerd_font() {
    # Install CaskaydiaCove Nerd Font Mono — the font used in alacritty and VSCodium.
    # macOS: handled by Brewfile-base cask. Windows/WSL: handled by up.sh.
    # This function is for native Linux only.
    if fc-list 2>/dev/null | grep -qi 'CaskaydiaCove'; then
        log "CaskaydiaCove Nerd Font already installed"
        return 0
    fi

    if ! command -v fc-cache >/dev/null 2>&1; then
        warn "fontconfig not found — skipping font installation"
        return 0
    fi

    log "installing CaskaydiaCove Nerd Font"
    local tmp; tmp=$(mktemp -d)
    curl -fsSL \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip" \
        -o "$tmp/CascadiaCode.zip"

    local font_dir="$HOME/.local/share/fonts/CaskaydiaCove"
    mkdir -p "$font_dir"

    # Extract Mono variants only — these map to "CaskaydiaCove Nerd Font Mono".
    # Uses Python stdlib zipfile to avoid an unzip dependency.
    python3 - <<PYEOF
import zipfile, os
with zipfile.ZipFile('$tmp/CascadiaCode.zip') as z:
    for name in z.namelist():
        if 'NerdFontMono' in name and name.endswith('.ttf'):
            dest = os.path.join('$font_dir', os.path.basename(name))
            with open(dest, 'wb') as f:
                f.write(z.read(name))
PYEOF

    fc-cache -f "$font_dir"
    rm -rf "$tmp"
    log "CaskaydiaCove Nerd Font installed"
}

ensure_homebrew_bundle() {
    # Run brew bundle for each Brewfile stowed to ~.
    # Brewfile-base (os/macos) installs shared desktop apps.
    # Brewfile-host (hosts/<host>) installs machine-specific apps and deps.
    for brewfile in ~/.Brewfile-base ~/.Brewfile-host; do
        [[ -f "$brewfile" ]] || continue
        log "brew bundle --file=$brewfile"
        brew bundle --file="$brewfile" --no-lock
    done
}

ensure_mise() {
    # Install mise if absent, then install all tools from .config/mise/config.toml.
    if ! command -v mise >/dev/null 2>&1; then
        log "installing mise"
        curl -fsSL https://mise.run | sh
        # Add to PATH for the remainder of this script
        export PATH="$HOME/.local/bin:$PATH"
    else
        log "mise $(mise --version) already installed"
    fi

    if [[ -f "$HOME/.config/mise/config.toml" ]]; then
        log "mise install (CLI tools + runtimes)"
        mise install --yes
    else
        warn "no mise config found at ~/.config/mise/config.toml — skipping"
    fi
}

stow_dir() {
    # stow_dir <package-parent-dir> [explicit packages...]
    # Auto-discovers top-level packages if none given. No-ops if dir missing.
    local parent="$1"; shift
    [[ -d "$parent" ]] || return 0

    local pkgs=("$@")
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        local d
        while IFS= read -r -d '' d; do
            pkgs+=("$(basename "$d")")
        done < <(find "$parent" -maxdepth 1 -mindepth 1 -type d -print0)
    fi
    [[ ${#pkgs[@]} -eq 0 ]] && return 0

    log "stow $parent -> ~ (${pkgs[*]})"
    stow --restow -d "$parent" -t "$HOME" "${pkgs[@]}"
}

load_macos_launch_agents() {
    local uid; uid="$(id -u)"
    shopt -s nullglob
    local plist
    for plist in "$HOME/Library/LaunchAgents/"*.plist; do
        # Extract the service label from the plist so we can check if it is
        # already loaded before stopping and restarting it.
        local label
        label=$(python3 -c "
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    pl = plistlib.load(f)
print(pl.get('Label', ''))
" "$plist" 2>/dev/null)
        if [[ -z "$label" ]]; then
            warn "could not read Label from $(basename "$plist") — skipping"
            continue
        fi
        if launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
            log "launch agent already loaded: $label"
        else
            log "loading launch agent: $label"
            launchctl bootout "gui/$uid" "$plist" >/dev/null 2>&1 || true
            launchctl bootstrap "gui/$uid" "$plist"
        fi
    done
    shopt -u nullglob
}

_stow_preflight() {
    # Simulate every stow operation that main() will perform and collect
    # conflicts. Exits with an error listing them all if any are found,
    # before any real change is made.
    local sim_target; sim_target=$(mktemp -d)
    local conflicts=0

    _sim_stow() {
        local parent="$1"; shift
        [[ -d "$parent" ]] || return 0
        local pkgs=("$@")
        if [[ ${#pkgs[@]} -eq 0 ]]; then
            local d
            while IFS= read -r -d '' d; do
                pkgs+=("$(basename "$d")")
            done < <(find "$parent" -maxdepth 1 -mindepth 1 -type d -print0)
        fi
        [[ ${#pkgs[@]} -eq 0 ]] && return 0
        local out
        out=$(stow -n --no-folding -d "$parent" -t "$sim_target" "${pkgs[@]}" 2>&1)
        # Conflicts appear as lines containing the target path as a real file
        local found
        found=$(echo "$out" | grep -E 'existing target is neither|cannot stow' || true)
        if [[ -n "$found" ]]; then
            # Translate simulated paths back to real home paths
            echo "$found" | sed "s|$sim_target|$HOME|g" >&2
            conflicts=$((conflicts + 1))
        fi
        # Pre-populate sim_target with what this layer would create, so
        # subsequent layers see a realistic state.
        stow --no-folding -d "$parent" -t "$sim_target" "${pkgs[@]}" 2>/dev/null || true
    }

    if _repo_is_locked; then
        _sim_stow "$DOTFILES/base" bash git nvim fish tmux alacritty mise
    else
        _sim_stow "$DOTFILES/base" bash git gnupg nvim ssh fish tmux alacritty mise
    fi

    case "$platform" in
        macos) _sim_stow "$DOTFILES/os/macos" ;;
        linux) _sim_stow "$DOTFILES/os/linux" ;;
        wsl)
            _sim_stow "$DOTFILES/os/linux" bash
            _sim_stow "$DOTFILES/os/wsl" git
            ;;
    esac

    [[ -d "$DOTFILES/hosts/$host" ]] && _sim_stow "$DOTFILES/hosts/$host"

    rm -rf "$sim_target"
    unset -f _sim_stow

    if [[ $conflicts -gt 0 ]]; then
        err "stow conflicts detected (see above).\n  Back up or remove the conflicting files, then re-run bootstrap.sh."
    fi
}

_repo_is_locked() {
    # Detect whether git-crypt has not yet been unlocked on this clone.
    # Encrypted blobs start with a 10-byte magic header: \x00GITCRYPT\x00
    local sentinel="$DOTFILES/secrets/env.sh"
    [[ -f "$sentinel" ]] || return 1  # no secrets file — assume unlocked
    python3 -c "
import sys
with open(sys.argv[1], 'rb') as f:
    sys.exit(0 if f.read(10) == b'\x00GITCRYPT\x00' else 1)
" "$sentinel" 2>/dev/null
}

main() {
    [[ -d "$DOTFILES" ]] || err "dotfiles not at $DOTFILES (override with DOTFILES=...)"

    local platform host
    platform="$(detect_platform)"
    host="$(normalize_hostname)"
    log "platform=$platform host=$host"

    case "$platform" in
        macos)     ensure_macos_prereqs ;;
        linux|wsl) ensure_linux_prereqs ;;
    esac

    # Pre-flight: dry-run all stow operations and report conflicts clearly
    # rather than aborting mid-run with a cryptic stow error.
    _stow_preflight

    # gnupg and ssh configs include encrypted files (.ssh/config.d/*, secrets/).
    # Stowing them while git-crypt is locked installs encrypted blobs as configs.
    if _repo_is_locked; then
        warn "git-crypt is locked — skipping gnupg and ssh stow"
        warn "run 'git-crypt unlock' then re-run bootstrap.sh to complete setup"
        log "stowing base configs (secrets excluded)"
        stow_dir "$DOTFILES/base" bash git nvim fish tmux alacritty mise
    else
        log "stowing base configs"
        stow_dir "$DOTFILES/base" bash git gnupg nvim ssh fish tmux alacritty mise
    fi

    case "$platform" in
        macos) stow_dir "$DOTFILES/os/macos" ;;
        linux) stow_dir "$DOTFILES/os/linux" ;;
        wsl)
            # WSL: only stow the shell/CLI layer from os/linux.
            # Alacritty runs on Windows; awesome WM is irrelevant.
            stow_dir "$DOTFILES/os/linux" bash
            # Explicit package list: os/wsl/windows/ is not a stow package.
            stow_dir "$DOTFILES/os/wsl" git
            ;;
    esac

    if [[ -d "$DOTFILES/hosts/$host" ]]; then
        stow_dir "$DOTFILES/hosts/$host"
    else
        warn "no host-specific configs for '$host' (expected $DOTFILES/hosts/$host)"
    fi

    if [[ "$platform" == "macos" ]]; then
        load_macos_launch_agents
    fi

    if [[ "$platform" == "wsl" ]]; then
        log "running Windows-side setup"
        bash "$DOTFILES/os/wsl/up.sh"
    fi

    # Install tools after configs are stowed so first-launch config is ready.
    # System tools (apt/brew) first, then mise for CLI tools and runtimes.
    # Font: macOS → Brewfile cask; WSL → up.sh; Linux → ensure_nerd_font.
    case "$platform" in
        linux|wsl)
            ensure_system_tools
            ensure_fisher
            ensure_mise
            ;;
        macos)
            ensure_homebrew_bundle
            ensure_fisher
            ensure_mise
            ;;
    esac

    if [[ "$platform" == "linux" ]]; then
        ensure_nerd_font
    fi

    log "bootstrap complete"
    log "next steps:"
    log "  1. Start a new shell (or: exec fish) to pick up Fish config"

}

main "$@"
