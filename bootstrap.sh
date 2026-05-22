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

ensure_linux_prereqs() {
    local missing=()
    for pkg in stow git-crypt; do
        command -v "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    [[ ${#missing[@]} -eq 0 ]] && return 0

    if   command -v apt-get >/dev/null 2>&1; then
        log "apt-get install ${missing[*]}"
        sudo apt-get update
        sudo apt-get install -y "${missing[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        log "dnf install ${missing[*]}"
        sudo dnf install -y "${missing[@]}"
    elif command -v pacman >/dev/null 2>&1; then
        log "pacman -S ${missing[*]}"
        sudo pacman -S --noconfirm "${missing[@]}"
    elif command -v nix-env >/dev/null 2>&1; then
        log "nix-env -iA ${missing[*]}"
        nix-env -iA "${missing[@]/#/nixpkgs.}"
    else
        err "missing prerequisites (${missing[*]}) and no known package manager available"
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

    log "bootstrap complete"
}

main "$@"
