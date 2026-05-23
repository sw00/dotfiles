#!/usr/bin/env bash
# os/wsl/up.sh — push dotfiles configs to the Windows side of any WSL2 machine.
# Called automatically by bootstrap.sh on WSL. Safe to re-run.
#
# Generic content lives under os/wsl/windows/.
# Host-specific overrides are read from hosts/<hostname>/ where they exist.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"
WINDOWS_SRC="$DOTFILES/os/wsl/windows"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }

# ── Require Windows interop ───────────────────────────────────────────────────
if ! command -v cmd.exe >/dev/null 2>&1; then
    warn "cmd.exe not available — skipping Windows-side setup"
    warn "(WSL interop disabled or running outside WSL?)"
    exit 0
fi

# Resolve Windows user paths via cmd.exe (avoids dependency on wslu/wslvar)
WIN_HOME=$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")
WIN_APPDATA=$(wslpath "$(cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r')")

# ── /etc/wsl.conf ─────────────────────────────────────────────────────────────
if [[ -f "$WINDOWS_SRC/wsl.conf" ]]; then
    log "installing /etc/wsl.conf"
    sudo cp -f "$WINDOWS_SRC/wsl.conf" /etc/wsl.conf
fi

# ── .wslconfig (host-specific hardware tuning) ────────────────────────────────
WSLCONFIG="$DOTFILES/hosts/$HOST/.wslconfig"
if [[ -f "$WSLCONFIG" ]]; then
    log "installing .wslconfig → $WIN_HOME/.wslconfig"
    cp -f "$WSLCONFIG" "$WIN_HOME/.wslconfig"
    warn ".wslconfig updated — restart WSL to apply: wsl.exe --shutdown"
else
    warn "no .wslconfig for host '$HOST' (expected hosts/$HOST/.wslconfig) — skipping"
fi

# ── Alacritty ─────────────────────────────────────────────────────────────────
# base.toml is shared; the host alacritty.toml imports it and adds overrides.
ALACRITTY_WIN="$WIN_APPDATA/Alacritty"
ALACRITTY_BASE="$DOTFILES/base/alacritty/.config/alacritty/base.toml"
ALACRITTY_HOST="$DOTFILES/hosts/$HOST/alacritty/.config/alacritty/alacritty.toml"

if [[ -f "$ALACRITTY_BASE" ]]; then
    mkdir -p "$ALACRITTY_WIN"
    if [[ -f "$ALACRITTY_HOST" ]]; then
        log "installing Alacritty config (base + $HOST override)"
        cp -f "$ALACRITTY_BASE" "$ALACRITTY_WIN/base.toml"
        cp -f "$ALACRITTY_HOST" "$ALACRITTY_WIN/alacritty.toml"
    else
        log "installing Alacritty config (base only — no host override for '$HOST')"
        cp -f "$ALACRITTY_BASE" "$ALACRITTY_WIN/alacritty.toml"
    fi
fi

# ── VSCodium ──────────────────────────────────────────────────────────────────
VSCODIUM_SRC="$WINDOWS_SRC/vscodium"
VSCODIUM_WIN="$WIN_APPDATA/VSCodium/User"

if [[ -f "$VSCODIUM_SRC/settings.json" ]]; then
    log "installing VSCodium settings"
    mkdir -p "$VSCODIUM_WIN"
    cp -f "$VSCODIUM_SRC/settings.json" "$VSCODIUM_WIN/settings.json"
fi

if [[ -f "$VSCODIUM_SRC/extensions.txt" ]]; then
    # Locate codium.cmd: system install, user install, Scoop, or Windows PATH.
    CODIUM_CMD=""
    for candidate in \
        "/mnt/c/Program Files/VSCodium/bin/codium.cmd" \
        "/mnt/c/Users/$USER/AppData/Local/Programs/VSCodium/bin/codium.cmd" \
        "$HOME/scoop/apps/vscodium/current/bin/codium.cmd"
    do
        [[ -f "$candidate" ]] && CODIUM_CMD="$candidate" && break
    done

    # Fallback: ask Windows itself
    if [[ -z "$CODIUM_CMD" ]]; then
        _win_path=$(cmd.exe /c 'where codium.cmd' 2>/dev/null | tr -d '\r' | head -1)
        [[ -n "$_win_path" ]] && CODIUM_CMD=$(wslpath "$_win_path") || true
    fi

    if [[ -n "$CODIUM_CMD" ]] && [[ -f "$CODIUM_CMD" ]]; then
        log "installing VSCodium extensions"
        grep -v '^#' "$VSCODIUM_SRC/extensions.txt" | grep -v '^$' \
        | while read -r ext; do
            "$CODIUM_CMD" --install-extension "$ext" --force 2>&1 \
                | grep -v 'already installed' || true
        done
    else
        warn "codium.cmd not found — install VSCodium, then re-run bootstrap.sh"
        warn "  winget install VSCodium.VSCodium"
    fi
fi

log "Windows-side setup complete"
log "Required Windows apps (install via winget if absent):"
log "  winget install Alacritty.Alacritty"
log "  winget install VSCodium.VSCodium"
log "  CaskaydiaCove Nerd Font: https://www.nerdfonts.com/font-downloads"
