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
        # apt
        apt:nvim)       echo neovim ;;   # Ubuntu 24.04 apt name
        apt:fd)         echo fd-find ;;
        apt:rg)         echo ripgrep ;;
        apt:delta)      echo git-delta ;;
        apt:git-lfs)    echo git-lfs ;;
        apt:wslview)    echo wslu ;;
        # dnf
        dnf:nvim)       echo neovim ;;
        dnf:fd)         echo fd-find ;;
        dnf:rg)         echo ripgrep ;;
        dnf:delta)      echo git-delta ;;
        *)              echo "$cmd" ;;
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
    # Install tools that must exist before mise runs:
    # login shell, terminal multiplexer, bootstrap deps, system integrations.
    local mgr; mgr="$(_detect_pkg_mgr)"
    [[ -n "$mgr" ]] || { warn "no package manager — skipping system tool installation"; return 0; }

    local wanted=(fish tmux git-lfs lf tig)
    # WSL-specific additions
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
        log "loading launch agent: $(basename "$plist")"
        launchctl bootout "gui/$uid" "$plist" >/dev/null 2>&1 || true
        launchctl bootstrap "gui/$uid" "$plist"
    done
    shopt -u nullglob
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

    log "stowing base configs"
    stow_dir "$DOTFILES/base" bash git gnupg nvim ssh fish tmux alacritty mise

    case "$platform" in
        macos) stow_dir "$DOTFILES/os/macos" ;;
        linux) stow_dir "$DOTFILES/os/linux" ;;
        wsl)
            # WSL: only stow the shell/CLI layer from os/linux.
            # Alacritty runs on Windows (copied by hosts/*/wsl/up.sh).
            # Awesome WM is irrelevant in WSL.
            stow_dir "$DOTFILES/os/linux" bash
            stow_dir "$DOTFILES/os/wsl"
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

    # Install tools after configs are stowed so first-launch config is ready.
    # System tools (apt/brew) first, then mise for CLI tools and runtimes.
    case "$platform" in
        linux|wsl)
            ensure_system_tools
            ensure_fisher
            ensure_mise
            ;;
        macos)
            ensure_fisher
            ensure_mise
            ;;
    esac

    log "bootstrap complete"
    log "next steps:"
    log "  1. Start a new shell (or: exec fish) to pick up Fish config"
    if [[ "$platform" == "wsl" ]] && [[ -f "$DOTFILES/hosts/$host/wsl/up.sh" ]]; then
        log "  2. Run hosts/$host/wsl/up.sh to set up Windows-side configs"
    fi
}

main "$@"
