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
WIN_LOCALAPPDATA=$(wslpath "$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')")

# ── Windows apps (winget) ────────────────────────────────────────────────────
WINGET_LIST="$WINDOWS_SRC/winget.txt"
if [[ -f "$WINGET_LIST" ]] && command -v winget.exe >/dev/null 2>&1; then
    log "installing Windows apps via winget"
    grep -v '^#' "$WINGET_LIST" | grep -v '^$' | while read -r pkg_id; do
        winget.exe install --id "$pkg_id" \
            --accept-source-agreements --accept-package-agreements \
            --silent 2>&1 | grep -Ev 'already installed|No applicable|found an existing' \
            || true
    done
else
    warn "winget.exe not found or winget.txt missing — skipping Windows app installation"
fi

# ── /etc/wsl.conf ─────────────────────────────────────────────────────────────
if [[ -f "$WINDOWS_SRC/wsl.conf" ]]; then
    log "installing /etc/wsl.conf"
    sudo cp -f "$WINDOWS_SRC/wsl.conf" /etc/wsl.conf
fi

# ── .wslconfig (host-specific hardware tuning) ────────────────────────────────
WSLCONFIG="$DOTFILES/hosts/$HOST/.wslconfig"
if [[ -f "$WSLCONFIG" ]]; then
    if ! diff -q "$WSLCONFIG" "$WIN_HOME/.wslconfig" >/dev/null 2>&1; then
        log "installing .wslconfig → $WIN_HOME/.wslconfig"
        cp -f "$WSLCONFIG" "$WIN_HOME/.wslconfig"
        warn ".wslconfig changed — restart WSL to apply: wsl.exe --shutdown"
    else
        log ".wslconfig unchanged"
    fi
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

# Install the WSL→git wrapper so VSCodium's git.path can point at it.
# The wrapper lives at %LOCALAPPDATA%\bin\git.cmd and simply calls wsl.exe git.
GIT_WRAPPER_DIR="$WIN_LOCALAPPDATA/bin"
GIT_WRAPPER="$GIT_WRAPPER_DIR/git.cmd"
if [[ -f "$VSCODIUM_SRC/wsl-git.cmd" ]]; then
    log "installing WSL git wrapper → $GIT_WRAPPER"
    mkdir -p "$GIT_WRAPPER_DIR"
    cp -f "$VSCODIUM_SRC/wsl-git.cmd" "$GIT_WRAPPER"
fi

if [[ -f "$VSCODIUM_SRC/settings.json" ]]; then
    log "installing VSCodium settings"
    mkdir -p "$VSCODIUM_WIN"
    # Substitute __WIN_LOCALAPPDATA__ with the real Windows path (backslash-
    # escaped for JSON).  Python is used to avoid bash/sed backslash hell.
    WIN_LOCALAPPDATA_WIN=$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')
    python3 - "$VSCODIUM_SRC/settings.json" "$VSCODIUM_WIN/settings.json" \
              "$WIN_LOCALAPPDATA_WIN" << 'PYEOF'
import sys
src, dst, win_path = sys.argv[1], sys.argv[2], sys.argv[3]
# JSON requires backslashes doubled; win_path arrives with single backslashes.
json_path = win_path.replace('\\', '\\\\')
with open(src) as f:
    content = f.read()
with open(dst, 'w') as f:
    f.write(content.replace('__WIN_LOCALAPPDATA__', json_path))
PYEOF
fi

if [[ -f "$VSCODIUM_SRC/extensions.txt" ]]; then
    # Locate codium.cmd: system install, user install, Scoop, or Windows PATH.
    CODIUM_CMD=""
    # winget installs to Program Files (system) or AppData/Local/Programs (user).
    for candidate in \
        "/mnt/c/Program Files/VSCodium/bin/codium.cmd" \
        "/mnt/c/Users/$USER/AppData/Local/Programs/VSCodium/bin/codium.cmd"
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
            cmd.exe /c "$(wslpath -w "$CODIUM_CMD")" --install-extension "$ext" --force 2>&1 \
                | grep -v 'already installed' || true
        done
    else
        warn "codium.cmd not found — install VSCodium, then re-run bootstrap.sh"
        warn "  winget install VSCodium.VSCodium"
    fi
fi

# ── Fonts ───────────────────────────────────────────────────────────────────────
# Write a PowerShell script to a temp file to avoid bash/PS escaping tangles.
# Per-user font dir (%LOCALAPPDATA%\Microsoft\Windows\Fonts) requires explicit
# HKCU registry entries to be visible to all Windows apps.
PS_FONT=$(mktemp --suffix=.ps1)
cat > "$PS_FONT" << 'EOF'
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$sentinel = Join-Path $fontDir "CaskaydiaCoveNerdFontMono-Regular.ttf"

if (Test-Path $sentinel) {
    Write-Host "==> CaskaydiaCove Nerd Font Mono already installed"
    exit 0
}

Write-Host "==> Downloading CaskaydiaCove Nerd Font..."
$tmp = Join-Path $env:TEMP "NerdFonts"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest `
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip" `
    -OutFile "$tmp\CascadiaCode.zip" -UseBasicParsing

Expand-Archive "$tmp\CascadiaCode.zip" -DestinationPath "$tmp\extracted" -Force
New-Item -ItemType Directory -Force -Path $fontDir | Out-Null

$regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
Get-ChildItem "$tmp\extracted" -Filter "*NerdFontMono*.ttf" | ForEach-Object {
    Copy-Item $_.FullName "$fontDir\" -Force
    Set-ItemProperty -Path $regPath `
        -Name ($_.BaseName + " (TrueType)") `
        -Value "$fontDir\$($_.Name)" `
        -Type String -Force
    Write-Host "    installed $($_.Name)"
}
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "==> Fonts installed - restart Alacritty to apply"
EOF

log "installing CaskaydiaCove Nerd Font on Windows"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PS_FONT")" 2>&1 || \
    warn "font installation failed — install manually from https://www.nerdfonts.com/font-downloads"
rm -f "$PS_FONT"

log "Windows-side setup complete"
