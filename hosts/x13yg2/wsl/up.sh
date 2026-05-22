#!/usr/bin/env bash
# up.sh — copy Windows-side files for x13yg2 from WSL
# Run after bootstrap.sh to set up the Windows desktop environment.
# Requires: WSL 2 with access to /mnt/c

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$SCRIPT_DIR/files"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }

# Resolve Windows user paths via cmd.exe (works without wslvar)
WIN_HOME=$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")
WIN_APPDATA=$(wslpath "$(cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r')")

# ── /etc/wsl.conf ──────────────────────────────────────────────────────────
if [[ -f "$FILES/wsl.conf" ]]; then
    log "installing /etc/wsl.conf"
    sudo cp -f "$FILES/wsl.conf" /etc/wsl.conf
fi

# ── ~/.wslconfig (Windows side) ────────────────────────────────────────────
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [[ -f "$DOTFILES_ROOT/hosts/x13yg2/.wslconfig" ]]; then
    log "installing .wslconfig → $WIN_HOME/.wslconfig"
    cp -f "$DOTFILES_ROOT/hosts/x13yg2/.wslconfig" "$WIN_HOME/.wslconfig"
    warn ".wslconfig updated — restart WSL to apply: wsl.exe --shutdown"
fi

# ── Alacritty ──────────────────────────────────────────────────────────────
ALACRITTY_BASE="$DOTFILES_ROOT/base/alacritty/.config/alacritty/base.toml"
ALACRITTY_HOST="$DOTFILES_ROOT/hosts/x13yg2/alacritty/.config/alacritty/alacritty.toml"

if [[ -f "$ALACRITTY_HOST" ]]; then
    log "installing Alacritty config"
    mkdir -p "$WIN_APPDATA/Alacritty"
    cp -f "$ALACRITTY_BASE" "$WIN_APPDATA/Alacritty/base.toml"
    cp -f "$ALACRITTY_HOST" "$WIN_APPDATA/Alacritty/alacritty.toml"
fi

log "Windows-side setup complete"
log "Install Alacritty on Windows if not already: winget install Alacritty.Alacritty"
log "Install CaskaydiaCove Nerd Font: https://www.nerdfonts.com/font-downloads"
