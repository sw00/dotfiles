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

# Mapping from command name → apt/dnf/pacman package name (where they differ)
declare -A PKG_APT=(
    [nvim]=neovim
    [fzf]=fzf
    [fd]=fd-find
    [rg]=ripgrep
    [fish]=fish
    [tmux]=tmux
    [stow]=stow
    [git-crypt]=git-crypt
)
declare -A PKG_DNF=(
    [nvim]=neovim
    [fd]=fd-find
    [rg]=ripgrep
)

_pkg_name() {
    local cmd="$1" mgr="$2"
    local map="PKG_${mgr^^}"
    echo "${!map[$cmd]:-$cmd}"
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

ensure_tools() {
    # Install the core interactive toolchain if not already present.
    # Called after stow so configs are in place before first launch.
    local mgr; mgr="$(_detect_pkg_mgr)"
    [[ -n "$mgr" ]] || { warn "no package manager — skipping tool installation"; return 0; }

    local wanted=(fish nvim tmux fzf fd rg)
    local missing=()
    for cmd in "${wanted[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    [[ ${#missing[@]} -eq 0 ]] && { log "core tools already installed"; return 0; }

    log "installing core tools via $mgr: ${missing[*]}"
    _install_pkgs "$mgr" "${missing[@]}"

    # asdf: not in most distro repos — install via official script if absent
    if ! command -v asdf >/dev/null 2>&1 && [[ ! -f "$HOME/.asdf/asdf.sh" ]]; then
        log "installing asdf"
        git clone https://github.com/asdf-vm/asdf.git "$HOME/.asdf" \
            --branch "$(git -C /tmp ls-remote --tags https://github.com/asdf-vm/asdf.git \
                | awk -F/ '{print $NF}' | grep '^v' | sort -V | tail -1)" 2>/dev/null \
            || git clone https://github.com/asdf-vm/asdf.git "$HOME/.asdf"
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
    stow_dir "$DOTFILES/base" bash git nvim ssh fish tmux

    case "$platform" in
        macos) stow_dir "$DOTFILES/os/macos" ;;
        linux) stow_dir "$DOTFILES/os/linux" ;;
        wsl)
            stow_dir "$DOTFILES/os/linux"
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

    # Install tools after configs are stowed so first-launch config is ready
    case "$platform" in
        linux|wsl) ensure_tools ;;
    esac

    log "bootstrap complete"
    log "next steps:"
    log "  1. Start a new shell (or: exec fish) to pick up Fish config"
    if [[ "$platform" == "wsl" ]] && [[ -f "$DOTFILES/hosts/$host/wsl/up.sh" ]]; then
        log "  2. Run hosts/$host/wsl/up.sh to set up Windows-side configs"
    fi
}

main "$@"
