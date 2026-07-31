#!/usr/bin/env bash
# =============================================================================
# check.sh — dotfiles test suite
#
# Usage:  ./check.sh
# Exit:   0 = all tests passed, 1 = one or more failures
#
# All tests are regression guards — labelled [GREEN].
# =============================================================================

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0; SKIP=0
FAILED=()
SECTION=""

# ── Colour output (suppressed when not a tty) ──────────────────────────────
_c() { [[ -t 1 ]] && printf '%b' "$1" || true; }
GRN='\033[0;32m'; RED='\033[0;31m'; YLW='\033[0;33m'
BLD='\033[1m';    RST='\033[0m'

# ── Test runner primitives ─────────────────────────────────────────────────
section() {
    SECTION="$*"
    printf '\n%b%s%b\n' "$(_c "$BLD")" "── $*" "$(_c "$RST")"
}

_ok()   { printf '  %b✓%b %s\n' "$(_c "$GRN")" "$(_c "$RST")" "$1"; PASS=$((PASS+1)); }
_fail() { printf '  %b✗%b %s\n' "$(_c "$RED")" "$(_c "$RST")" "$1"; FAIL=$((FAIL+1)); FAILED+=("[$SECTION] $1"); }
_skip() { printf '  %b○%b %s  (needs: %s)\n' "$(_c "$YLW")" "$(_c "$RST")" "$1" "$2"; SKIP=$((SKIP+1)); }

# Run a test: pass if the command exits 0, fail otherwise.
# Both stdout and stderr from the command are suppressed.
check() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then _ok "$name"; else _fail "$name"; fi
}

# Pass if an ERE pattern IS found in a file
check_has() {
    local name="$1" pattern="$2" file="$3"
    if grep -qE "$pattern" "$file" 2>/dev/null; then _ok "$name"; else _fail "$name"; fi
}

# Pass if an ERE pattern is NOT found in a file
check_not() {
    local name="$1" pattern="$2" file="$3"
    if ! grep -qE "$pattern" "$file" 2>/dev/null; then _ok "$name"; else _fail "$name"; fi
}

# ── Stow helpers ───────────────────────────────────────────────────────────
# For cross-layer conflict detection we need a persistent scratch $HOME.
# stow_layer: actually stow packages so later layers see a realistic state.
# check_stow: simulate the layer under test and report pass/fail.

STOW_TMP=""
stow_begin() { STOW_TMP=$(mktemp -d); }
stow_end()   { [[ -n "${STOW_TMP:-}" ]] && rm -rf "$STOW_TMP"; STOW_TMP=""; }

stow_layer() {
    # Lay down a prerequisite layer for real (not simulated).
    # --no-folding prevents directory-level symlinks so subsequent layers
    # from different stow dirs can target the same directories.
    local parent="$1"; shift
    [[ -d "$parent" ]] || return 0
    stow --no-folding -d "$parent" -t "$STOW_TMP" "$@" 2>/dev/null
}

check_stow() {
    # Simulate stowing packages from parent into STOW_TMP; fail on conflicts
    local name="$1" parent="$2"; shift 2
    local pkgs=("$@")

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        mapfile -t pkgs < <(
            find "$parent" -maxdepth 1 -mindepth 1 -type d \
                -printf '%f\n' 2>/dev/null | sort
        )
    fi

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        _skip "$name" "no packages in $parent"
        return
    fi

    local out rc
    out=$(stow -n -d "$parent" -t "$STOW_TMP" "${pkgs[@]}" 2>&1)
    rc=$?

    if [[ $rc -ne 0 ]] || \
       echo "$out" | grep -qE 'existing target is neither|cannot stow'; then
        _fail "$name"
    else
        _ok "$name"
    fi
}

# =============================================================================
# 1. SHELL SCRIPT SYNTAX  [GREEN]
# =============================================================================
section "Shell script syntax  [GREEN]"

mapfile -t ALL_SCRIPTS < <(
    find "$DOTFILES" \
        -not -path '*/.git/*' \
        -not -path '*/nix/*' \
        -not -path '*/tmux/plugins/*' \
        -not -path '*/secrets/*' \
        \( -name '*.sh' -o -name '*.bash' \) \
        -type f | sort
)

for s in "${ALL_SCRIPTS[@]}"; do
    rel="${s#"$DOTFILES/"}"
    check "bash -n: $rel" bash -n "$s"
done

if command -v shellcheck >/dev/null 2>&1; then
    for s in "${ALL_SCRIPTS[@]}"; do
        rel="${s#"$DOTFILES/"}"
        check "shellcheck: $rel" shellcheck -S warning "$s"
    done
else
    _skip "shellcheck (all scripts)" "shellcheck not installed"
fi


# =============================================================================
# 2. STOW INTEGRITY  [GREEN]
# =============================================================================
section "Stow integrity — base packages  [GREEN]"

stow_begin
# base/gnupg removed: stowing it alongside os/*/gnupg causes a conflict on
# the same target file (gpg-agent.conf). gnupg is now stowed per-OS only.
# base/bash removed: .profile is stock Ubuntu boilerplate; PATH additions
# are handled by fish_add_path. Not stowing avoids conflicts on fresh machines.
check_stow "base: git nvim ssh fish tmux alacritty mise pi sesh" \
    "$DOTFILES/base" git nvim ssh fish tmux alacritty mise pi sesh
stow_end

# ── Linux stack: base → os/linux ───
section "Stow integrity — Linux stack  [GREEN]"

stow_begin
stow_layer "$DOTFILES/base" git nvim ssh fish tmux alacritty mise pi sesh
check_stow "os/linux: alacritty" \
    "$DOTFILES/os/linux" alacritty
stow_end

# ── macOS stack: base → os/macos → hosts/mbpm3 ───
section "Stow integrity — macOS stack  [GREEN]"

stow_begin
stow_layer "$DOTFILES/base" git nvim ssh fish tmux pi sesh
check_stow "os/macos: brew gnupg" \
    "$DOTFILES/os/macos" brew gnupg

stow_layer "$DOTFILES/os/macos" brew gnupg
check_stow "hosts/mbpm3: alacritty brew fish key_remap mise aerospace" \
    "$DOTFILES/hosts/mbpm3" alacritty brew fish key_remap mise aerospace
stow_end

# ── WSL stack: base → os/linux → os/wsl ───
# os/wsl/windows/ holds content for the Windows side (pushed by up.sh, not stowed).
# Stow packages are listed explicitly in bootstrap.sh (git, gnupg, alacritty).
section "Stow integrity — WSL stack  [GREEN]"

stow_begin
stow_layer "$DOTFILES/base" git nvim ssh fish tmux alacritty mise pi sesh
check_stow "os/wsl: git gnupg alacritty" "$DOTFILES/os/wsl" git gnupg alacritty
stow_end

check "os/wsl/up.sh exists" \
    test -f "$DOTFILES/os/wsl/up.sh"

check "os/wsl/gnupg: pinentry-wsl.sh exists" \
    test -f "$DOTFILES/os/wsl/gnupg/.gnupg/pinentry-wsl.sh"

check "os/linux: awesome/ removed (dead native-Linux WM)" \
    bash -c "! test -d '$DOTFILES/os/linux/awesome'"

check "os/wsl/gnupg: pinentry-wsl.sh is executable" \
    test -x "$DOTFILES/os/wsl/gnupg/.gnupg/pinentry-wsl.sh"

check "os/wsl/windows/wsl.conf exists" \
    test -f "$DOTFILES/os/wsl/windows/wsl.conf"

check_has "bootstrap: WSL calls os/wsl/up.sh" \
    'os/wsl/up.sh' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: os/wsl stow is explicit (git gnupg alacritty)" \
    'stow_dir.*os/wsl.*git gnupg alacritty' "$DOTFILES/bootstrap.sh"

# WSL host dirs hold only bare files (.wslconfig). Stow packages for the WSL
# platform live in os/wsl (alacritty); Windows-side app configs live in
# os/wsl/windows (komorebi, pushed by up.sh).
for wsl_host in x13yg2 x1eg2; do
    check "hosts/$wsl_host: no stow packages (WSL platform configs live in os/wsl)" \
        bash -c "! find '$DOTFILES/hosts/$wsl_host' -mindepth 1 -maxdepth 1 -type d | grep -q ."
done


# =============================================================================
# 3. CONFIG PARSABILITY  [GREEN]
# =============================================================================
section "Config parsability  [GREEN]"

# tmux: start a server against the config in an isolated socket, then kill it
check "tmux: config parses without errors" bash -c "
    tmux -L dotfiles_check \
         -f '$DOTFILES/base/tmux/.config/tmux/tmux.conf' \
         start-server 2>/dev/null
    rc=\$?
    tmux -L dotfiles_check kill-server 2>/dev/null || true
    exit \$rc
"

# git: 'config -l' exits 128 on malformed files
check "git: .gitconfig is parseable" \
    git config --file "$DOTFILES/base/git/.gitconfig" -l

# fish: parse-only check (skipped if fish is not installed)
FISH_CFG="$DOTFILES/base/fish/.config/fish/config.fish"
if command -v fish >/dev/null 2>&1; then
    check "fish: config.fish parses" fish --no-execute "$FISH_CFG"
    while IFS= read -r -d '' _cf; do
        check "fish: ${_cf#"$DOTFILES/"} parses" fish --no-execute "$_cf"
    done < <(find "$DOTFILES/base/fish" "$DOTFILES/hosts" -path '*conf.d*' -name '*.fish' -print0 2>/dev/null)
else
    _skip "fish: config.fish parses" "fish not installed"
fi


# =============================================================================
# 4. REPOSITORY STRUCTURE
# =============================================================================
section "Repository structure  [GREEN]"

# Every platform needs its os/ directory
check "os/wsl/ directory exists" \
    test -d "$DOTFILES/os/wsl"

# The machine running check.sh must have a matching host directory.
# Skipped in CI: the runner hostname is ephemeral and has no host config.
HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"
if [[ -z "${CI:-}" ]]; then
    check "hosts/$HOST/ exists for current machine ($HOST)" \
        test -d "$DOTFILES/hosts/$HOST"
else
    _skip "hosts/$HOST/ exists for current machine ($HOST)" "CI environment"
fi

# =============================================================================
# 5. FISH CONFIG
# =============================================================================
section "Fish config  [GREEN]"

check_not \
    "config.fish: Fisher URL is not the deprecated git.io shortlink" \
    'git\.io/fisher' \
    "$FISH_CFG"

check_not \
    "config.fish: gpg-connect-agent not called before interactive guard" \
    'gpg-connect-agent' \
    <(awk '/is-interactive/{exit} {print}' "$FISH_CFG")

check_has \
    "config.fish: mise activate is present" \
    'mise activate' \
    "$FISH_CFG"

# ssh-agent conf.d: one shared agent on a fixed socket, skipped when the
# platform already provides one (macOS launchd).
AGENT_CFG="$DOTFILES/base/fish/.config/fish/conf.d/ssh-agent.fish"

check "fish: ssh-agent conf.d exists" \
    test -f "$AGENT_CFG"

check_has \
    "ssh-agent.fish: skipped when platform provides an agent" \
    'not set -q SSH_AUTH_SOCK' \
    "$AGENT_CFG"

check_has \
    "ssh-agent.fish: fixed socket path enables cross-shell reuse" \
    'agent\.sock' \
    "$AGENT_CFG"

check_has \
    "ssh-agent.fish: alive-but-empty agent is adopted (probe != 2)" \
    'probe -ne 2' \
    "$AGENT_CFG"


# =============================================================================
# 6. TMUX CONFIG
# =============================================================================
section "Tmux config  [GREEN]"

TMUX_CFG="$DOTFILES/base/tmux/.config/tmux/tmux.conf"

check_has \
    "tmux: clipboard has platform guard (if-shell Darwin)" \
    'if-shell.*Darwin' \
    "$TMUX_CFG"


# =============================================================================
# 7. GIT CONFIG
# =============================================================================
section "Git config  [GREEN]"

# The GCM helper path contains a space; unquoted it splits at runtime
# ('/mnt/c/Program: No such file or directory'). Must use ! + \" quoting.
check_has \
    'gitconfig-wsl: credential helper is shell-quoted (space in Program Files)' \
    'helper = !\\"' \
    "$DOTFILES/os/wsl/git/.gitconfig-wsl"

# Windows-side git config (os/wsl/windows/git/.gitconfig) — pushed to
# %USERPROFILE%\.gitconfig by up.sh.  Must stay in lockstep with base for
# the identity / signing blocks; the WSL-only and Linux-only blocks from
# base are dropped here (asserted absent so they can't creep back).
WIN_GITCFG="$DOTFILES/os/wsl/windows/git/.gitconfig"
check "win-git: .gitconfig exists and is parseable" \
    test -f "$WIN_GITCFG" && \
    git config --file "$WIN_GITCFG" -l
check_has \
    'win-git: user.signingkey matches base (GPG key parity)' \
    'signingkey = 0x69EABBAB2FFE0374' \
    "$WIN_GITCFG"
check_has \
    'win-git: commit.gpgSign = true (parity with base)' \
    'gpgSign = true' \
    "$WIN_GITCFG"
check_has \
    'win-git: gpg.program is absolute (Windows has no /usr/bin on PATH)' \
    'program = C:/Program Files/GnuPG/bin/gpg.exe' \
    "$WIN_GITCFG"
check_not \
    'win-git: no WSL-only [include] path = ~/.gitconfig-wsl' \
    '^path = ~/\.gitconfig-wsl' \
    "$WIN_GITCFG"
check_not \
    'win-git: no Linux-only etckeeper includeIf' \
    '^gitdir:/etc/' \
    "$WIN_GITCFG"
check_not \
    'win-git: no delta pager (delta not installed on Windows)' \
    '^pager = delta' \
    "$WIN_GITCFG"
check_not \
    'win-git: no LFS filter (git-lfs not installed on Windows; required=true breaks clones)' \
    '^\[filter "lfs"\]' \
    "$WIN_GITCFG"
check_has \
    'up.sh: Windows .gitconfig install present' \
    'WIN_GITCFG_SRC' \
    "$DOTFILES/os/wsl/up.sh"
check_has \
    'up.sh: GPG signing subkey exported from WSL to Windows' \
    'export-secret-subkeys' \
    "$DOTFILES/os/wsl/up.sh"
check_has \
    'winget.txt: Gpg4win present (Windows-side GPG GUI for commit signing)' \
    'GnuPG.Gpg4win' \
    "$DOTFILES/os/wsl/windows/winget.txt"

# SSH config must not contain duplicate Host stanzas
check "ssh/config.d/lan.conf: no duplicate Host entries" bash -c "
    dupes=\$(grep -hE '^Host ' '$DOTFILES/base/ssh/.ssh/config.d/lan.conf' \
        | awk '{print \$2}' | sort | uniq -d)
    [[ -z \"\$dupes\" ]]
"


# =============================================================================
# 8. NEOVIM
# =============================================================================
section "Neovim  [GREEN]"

LSPCFG="$DOTFILES/base/nvim/.config/nvim/lua/plugins/lspconfig.lua"

check_has \
    "nvim: lazydev.nvim is referenced in lspconfig" \
    'lazydev' \
    "$LSPCFG"


# =============================================================================
# 9. ALACRITTY
# =============================================================================
section "Alacritty  [GREEN]"

check_has \
    "alacritty (linux): config uses 'import' for shared base" \
    '^import' \
    "$DOTFILES/os/linux/alacritty/.config/alacritty/alacritty.toml"

check_has \
    "alacritty (mbpm3): config uses 'import' for shared base" \
    '^import' \
    "$DOTFILES/hosts/mbpm3/alacritty/.config/alacritty/alacritty.toml"

check_has \
    "alacritty (wsl platform): config uses 'import' for shared base" \
    '^import' \
    "$DOTFILES/os/wsl/alacritty/.config/alacritty/alacritty.toml"

check "alacritty (wsl platform): stow package exists" \
    test -d "$DOTFILES/os/wsl/alacritty"

check_has "up.sh: alacritty falls back to os/wsl platform config" \
    'ALACRITTY_PLATFORM' "$DOTFILES/os/wsl/up.sh"

check "komorebi: default config exists in os/wsl/windows" \
    test -f "$DOTFILES/os/wsl/windows/komorebi/config.json"

check "komorebi: default config is valid JSON" \
    python3 -m json.tool "$DOTFILES/os/wsl/windows/komorebi/config.json"

check "x13yg2: .wslconfig exists" \
    test -f "$DOTFILES/hosts/x13yg2/.wslconfig"

check "x1eg2: .wslconfig exists" \
    test -f "$DOTFILES/hosts/x1eg2/.wslconfig"

check "komorebi: default whkdrc exists in os/wsl/windows" \
    test -f "$DOTFILES/os/wsl/windows/komorebi/whkdrc"


check_has "up.sh: komorebi config installation present" \
    'KOMOREBI' "$DOTFILES/os/wsl/up.sh"

check_has "up.sh: whkdrc installation present" \
    'whkdrc' "$DOTFILES/os/wsl/up.sh"

check "alacritty: base.toml exists in base/alacritty" \
    test -f "$DOTFILES/base/alacritty/.config/alacritty/base.toml"

# ── AeroSpace (macOS tiling WM, komorebi counterpart) ────────────────────
check "aerospace: config exists" \
    test -f "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

check_has "aerospace: start-at-login enabled" \
    'start-at-login = true' "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

check_has "aerospace: alt-q close (aligned with komorebi)" \
    'alt-q = .close.' "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

check_has "aerospace: alt-h/j/k/l focus (consistent with komorebi)" \
    'alt-h = .focus left.' "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

check_has "aerospace: alt-shift-h/j/k/l move (consistent with komorebi)" \
    'alt-shift-h = .move left.' "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

check_has "aerospace: alt-1-0 workspace (consistent with komorebi)" \
    'alt-1 = .workspace 1.' "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

check_has "aerospace: alt-shift-1-0 move-to-workspace (consistent with komorebi)" \
    'alt-shift-1 = .move-node-to-workspace 1.' "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

check_has "aerospace: alt-minus/equal resize (consistent with komorebi)" \
    'alt-minus = .resize smart' "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

check_has "whkdrc: alt-minus resize (aligned with aerospace)" \
    'komorebic resize \-50' "$DOTFILES/os/wsl/windows/komorebi/whkdrc"

check_has "whkdrc: alt-equal resize (aligned with aerospace)" \
    'komorebic resize \+50' "$DOTFILES/os/wsl/windows/komorebi/whkdrc"

# alt-tab: both platforms do workspace back-and-forth
check_has "aerospace: alt-tab = workspace-back-and-forth" \
    'alt-tab = .workspace-back-and-forth.' "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

check_has "whkdrc: alt-tab = focus-last-workspace (aligned with AeroSpace back-and-forth)" \
    'focus-last-workspace' "$DOTFILES/os/wsl/windows/komorebi/whkdrc"

check_has "aerospace: alt-shift-tab move-workspace-to-monitor" \
    'alt-shift-tab' "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

# Workspace 8-10 reachable on both platforms
check_has "aerospace: alt-8 workspace 8" \
    'alt-8 = .workspace 8.' "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

check_has "whkdrc: alt-8 = focus-workspace 7" \
    'alt \+ 8.*focus-workspace 7' "$DOTFILES/os/wsl/windows/komorebi/whkdrc"

# No redundant j/k monitor bindings in whkdrc (they duplicated h/l on horizontal setup)
check_not "whkdrc: no alt-ctrl-j/k monitor bindings (removed as redundant)" \
    'alt \+ ctrl \+ [jk].*cycle-monitor' "$DOTFILES/os/wsl/windows/komorebi/whkdrc"

# move-to-monitor is directional (not all-same-no-args)
check_has "whkdrc: alt-shift-ctrl-h sends to monitor 0" \
    'move-to-monitor 0' "$DOTFILES/os/wsl/windows/komorebi/whkdrc"

check_has "whkdrc: alt-shift-ctrl-l sends to monitor 1" \
    'move-to-monitor 1' "$DOTFILES/os/wsl/windows/komorebi/whkdrc"

# No duplicate layout bindings in AeroSpace
check_not "aerospace: no duplicate alt-slash layout binding" \
    'alt-slash' "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

check_not "aerospace: no duplicate alt-comma layout binding" \
    'alt-comma' "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

check_has "aerospace: workspace 1-5 → U2722DE / LS27C31x / main" \
    "'U2722DE', 'LS27C31x'" "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

check_has "aerospace: workspace 6-10 → S2421HN / built-in / main" \
    "'S2421HN', 'built-in'" "$DOTFILES/hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml"

# Komorebi OS default: consistent BSP layout, no per-workspace layout variety
check_not "komorebi (os/wsl): no per-workspace layout variety (all BSP)" \
    'VerticalStack\|HorizontalStack\|Rows\|Grid\|UltrawideVerticalStack\|RightMainVerticalStack' \
    "$DOTFILES/os/wsl/windows/komorebi/config.json"

# Float rules: brave/obsidian float on Windows (kept from host config promotion; AeroSpace
# on macOS does not have explicit float rules for these, so they tile there by default).
check_has "komorebi (os/wsl): brave.exe in float_rules (upstream promoted from host)" \
    'brave\.exe' "$DOTFILES/os/wsl/windows/komorebi/config.json"

check_has "komorebi (os/wsl): obsidian.exe in float_rules (upstream promoted from host)" \
    'obsidian\.exe' "$DOTFILES/os/wsl/windows/komorebi/config.json"

# Flameshot casing consistent
check_has "komorebi (os/wsl): Flameshot.exe uppercase F (correct Windows exe name)" \
    'Flameshot\.exe' "$DOTFILES/os/wsl/windows/komorebi/config.json"


# =============================================================================
# 10. MISE  [GREEN]
# =============================================================================
section "Mise config  [GREEN]"

MISE_CFG="$DOTFILES/base/mise/.config/mise/config.toml"

check "mise: config.toml exists in base/mise stow package" \
    test -f "$MISE_CFG"

check_has "mise: neovim is managed by mise (not snap/apt)" \
    'neovim' "$MISE_CFG"

check_has "mise: fzf is managed by mise" \
    'fzf' "$MISE_CFG"

check_has "mise: node runtime is declared" \
    'node' "$MISE_CFG"

check_has "mise: python runtime is declared" \
    'python' "$MISE_CFG"

check_has "mise: tmux is managed by mise (not apt/brew)" \
    '^tmux ' "$MISE_CFG"

check_has "mise: sesh managed by mise (ubi backend)" \
    'ubi:joshmedeski/sesh' "$MISE_CFG"

check_has "mise: lf managed by mise (ubi backend)" \
    'ubi:gokcehan/lf' "$MISE_CFG"

check_has "mise: git-lfs managed by mise" \
    'git-lfs' "$MISE_CFG"

check_has "mise: devops tools declared (kubectl, helm, k9s)" \
    'kubectl' "$MISE_CFG"

check_has "mise: mise itself in macOS Brewfile-base (Homebrew install beats curl on macOS)" \
    'brew "mise"' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "mbpm3 mise: d2 declared (was Homebrew)" \
    'd2' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check_has "mbpm3 mise: websocat declared (was Homebrew)" \
    'websocat' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check "bootstrap: macOS calls ensure_homebrew_bundle" \
    grep -q 'ensure_homebrew_bundle' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: app-trim migration defined (2026-07 lean pass)" \
    'migrate_app_trim()' "$DOTFILES/bootstrap.sh"

check "bootstrap: app-trim migration called on macOS after brew bundle" bash -c "
    grep -A1 '^            ensure_homebrew_bundle\$' '$DOTFILES/bootstrap.sh' \
        | grep -q 'migrate_app_trim'
"

# ── Post-refactor invariants ──────────────────────────────────────────────────
check_has "up.sh: winget summary report present (✓ installed / ⚠ failed / ✗ not found)" \
    'installed,.*failed,.*not found' "$DOTFILES/os/wsl/up.sh"

check_has "bootstrap: privileged gate does git-crypt unlock before stow" \
    'git-crypt unlock' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: _repo_is_locked guard at phase 1a gate" \
    '_repo_is_locked' "$DOTFILES/bootstrap.sh"

check "os/wsl/windows/winget.txt exists" \
    test -f "$DOTFILES/os/wsl/windows/winget.txt"

check_has "winget.txt: Alacritty entry present" \
    'Alacritty.Alacritty' "$DOTFILES/os/wsl/windows/winget.txt"

check_has "winget.txt: VSCodium entry present" \
    'VSCodium.VSCodium' "$DOTFILES/os/wsl/windows/winget.txt"

check_has "bootstrap: WSL stows os/wsl gnupg (pinentry-wsl)" \
    'stow_dir.*os/wsl.*gnupg' \
    "$DOTFILES/bootstrap.sh"

# os/macos/gnupg stows only pinentry-ide.sh (static, no $HOME).
# gpg-agent.conf is written by bootstrap.sh ensure_macos_gpg() with $HOME
# expanded — same pattern as the WSL pinentry in up.sh.
check "os/macos/gnupg: pinentry-ide.sh exists (stowed)" \
    test -f "$DOTFILES/os/macos/gnupg/.gnupg/pinentry-ide.sh"

check "os/macos/gnupg: gpg-agent.conf NOT stow-managed (written by bootstrap)" \
    bash -c "! test -f '$DOTFILES/os/macos/gnupg/.gnupg/gpg-agent.conf'"

check_has "bootstrap: ensure_macos_gpg writes gpg-agent.conf with \$HOME pinentry-ide" \
    'pinentry-program.*HOME.*pinentry-ide' "$DOTFILES/bootstrap.sh"

check "base/gnupg removed (conflict source)" \
    bash -c "! test -d '$DOTFILES/base/gnupg'"

check_has "bootstrap: git-crypt lock guard present" \
    '_repo_is_locked' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: tig in _install_system_packages (merged prereqs + system tools)" \
    'wanted=.*tig' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: pinentry-gtk2 in WSL system packages" \
    'pinentry-gtk2' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: _install_system_packages merges prereqs + system tools" \
    '_install_system_packages' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: _resolve_gitcrypt_key (env > arg > TTY resolution)" \
    '_resolve_gitcrypt_key' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: _ensure_wsl_conf (privileged gate, moved from up.sh)" \
    '_ensure_wsl_conf' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: _ensure_wsl_gpg reloads gpg-agent (moved from up.sh)" \
    'gpg-connect-agent reloadagent' "$DOTFILES/bootstrap.sh"

# gpg-agent does not expand ~ in pinentry-program, so up.sh must write
# gpg-agent.conf with $HOME expanded — not stow-managed.
check "os/wsl/gnupg: gpg-agent.conf NOT stow-managed (written by up.sh)" \
    bash -c "! test -f '$DOTFILES/os/wsl/gnupg/.gnupg/gpg-agent.conf'"

check_has "bootstrap: _ensure_wsl_gpg writes gpg-agent.conf (moved from up.sh)" \
    'pinentry-program.*HOME.*pinentry-wsl' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: _ensure_wsl_gpg defined" \
    '_ensure_wsl_gpg' "$DOTFILES/bootstrap.sh"

check_has "mise: shellcheck declared" \
    'shellcheck' "$MISE_CFG"

# ── Tools / desktop audit ───────────────────────────────────────────────────────────
check_not "mise: work-specific tools not in global config" \
    'kubeseal\|kustomize\|argocd\|opentofu\|^helm' "$MISE_CFG"

check "hosts/mbpm3: work mise tools declared" \
    test -f "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check_has "hosts/mbpm3: mise work tools include helm" \
    'helm' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check_has "Brewfile-host: monokle tracked" \
    'monokle' "$DOTFILES/hosts/mbpm3/brew/.Brewfile-host"

check_has "Brewfile-base: aerospace present (primary WM on all macs)" \
    'cask "aerospace"' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "Brewfile-base: vscodium present (core desktop app, cf. winget.txt)" \
    'cask "vscodium"' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "hosts/mbpm3: stern in work mise tools (was asdf)" \
    'stern' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check_has "hosts/mbpm3: k3d in work mise tools (was asdf)" \
    'k3d' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check_has "hosts/mbpm3: awscli in work mise tools (was asdf)" \
    'awscli' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check_has "bootstrap: stow_dir handles unowned dir symlinks (asdf→mise migration)" \
    'existing target is not owned by stow' "$DOTFILES/bootstrap.sh"



check_has "Brewfile-base: tig present (moved from host)" \
    'brew "tig"' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "Brewfile-base: graphviz present (moved from host)" \
    'brew "graphviz"' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "Brewfile-base: obsidian present" \
    'obsidian' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "Brewfile-base: flameshot present" \
    'flameshot' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "hosts/mbpm3: work.fish conf.d exists" \
    'flyl' "$DOTFILES/hosts/mbpm3/fish/.config/fish/conf.d/work.fish"

check_has "winget.txt: Bitwarden present" \
    'Bitwarden.Bitwarden' "$DOTFILES/os/wsl/windows/winget.txt"

check_has "winget.txt: Brave present" \
    'Brave.Brave' "$DOTFILES/os/wsl/windows/winget.txt"

check_has "winget.txt: Obsidian present" \
    'Obsidian.Obsidian' "$DOTFILES/os/wsl/windows/winget.txt"

check_has "winget.txt: Flameshot present" \
    'Flameshot.Flameshot' "$DOTFILES/os/wsl/windows/winget.txt"

check_has "winget.txt: komorebi present" \
    'komorebi' "$DOTFILES/os/wsl/windows/winget.txt"

check_has "winget.txt: whkd present" \
    'whkd' "$DOTFILES/os/wsl/windows/winget.txt"

check_has "winget.txt: PyCharm Community present" \
    'JetBrains.PyCharm.Community' "$DOTFILES/os/wsl/windows/winget.txt"

check_has "winget.txt: Firefox Developer Edition present" \
    'Mozilla.Firefox.DeveloperEdition' "$DOTFILES/os/wsl/windows/winget.txt"

check_has "winget.txt: Git for Windows present (required for GCM in gitconfig-wsl)" \
    'Git.Git' "$DOTFILES/os/wsl/windows/winget.txt"

# ── Base sets: packages common to every machine of a platform ────────────────
BREW_BASE="$DOTFILES/os/macos/brew/.Brewfile-base"

for _pkg in stow git git-crypt gnupg pinentry-mac fish; do
    check_has "Brewfile-base: $_pkg present (every mac, not host-only)" \
        "brew \"$_pkg\"" "$BREW_BASE"
done

# Set 3: system CLI common to all platforms (cf. ensure_system_tools).
for _pkg in wireguard-tools pstree mosh; do
    check_has "Brewfile-base: $_pkg present (parity with ensure_system_tools)" \
        "brew \"$_pkg\"" "$BREW_BASE"
done

# Set 1: cross-platform desktop apps — each base macOS cask has a winget twin.
# Platform-only apps are excluded by design: aerospace
# (macOS), komorebi/whkd/Git.Git (Windows).
while IFS='|' read -r _cask _wid; do
    check "parity: $_cask (brew) ↔ $_wid (winget)" bash -c \
        'grep -q "cask \"$1\"" "$2" && grep -qx "$3" "$4"' \
        _ "$_cask" "$BREW_BASE" "$_wid" "$DOTFILES/os/wsl/windows/winget.txt"
done <<'PARITY'
alacritty|Alacritty.Alacritty
bitwarden|Bitwarden.Bitwarden
brave-browser|Brave.Brave
obsidian|Obsidian.Obsidian
vscodium|VSCodium.VSCodium
flameshot|Flameshot.Flameshot
telegram|Telegram.TelegramDesktop
firefox@developer-edition|Mozilla.Firefox.DeveloperEdition
PARITY

check_has "Brewfile-base: CaskaydiaCove font cask present" \
    'font-caskaydia-cove-nerd-font' \
    "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "bootstrap: ensure_nerd_font defined" \
    'ensure_nerd_font' "$DOTFILES/bootstrap.sh"

check "bootstrap: ensure_nerd_font called for linux" bash -c "
    grep -q 'platform.*linux' '$DOTFILES/bootstrap.sh' &&
    grep -q 'ensure_nerd_font' '$DOTFILES/bootstrap.sh'
"

check_has "up.sh: font PS1 script targets NerdFontMono" \
    'NerdFontMono' "$DOTFILES/os/wsl/up.sh"

check_has "alacritty base.toml: font family is CaskaydiaCove Nerd Font Mono" \
    'CaskaydiaCove Nerd Font Mono' \
    "$DOTFILES/base/alacritty/.config/alacritty/base.toml"


# =============================================================================
# 11. PI SHARED-CORE BOUNDARY
# =============================================================================
section "Pi shared-core boundary (no deployment-specific leakage)"

# The shared core under base/pi/.pi/agent/ is copied verbatim onto every
# deployment (laptop stow, agentbox copy). It must stay generic: no knowledge
# of the Telegram bridge, the agentbox appliance, or any host-specific overlay.
# Those concerns live in their host repos (e.g. sw00/homelab owns tg-status /
# confirmation-gate / pi-settings.json). This guard prevents regressions like
# the [telegram] prefix that once leaked into model-switch.ts.
check "pi shared core: no telegram/agentbox/tg-* references (deployment leakage)" \
    bash -c "! grep -rEq 'telegram|agentbox|tg-status|tg-session|confirmation-gate|cf-gateway|pi-telegram' \
        '$DOTFILES/base/pi/.pi/agent/extensions' \
        '$DOTFILES/base/pi/.pi/agent/agents' \
        '$DOTFILES/base/pi/.pi/agent/APPEND_SYSTEM.md' \
        '$DOTFILES/base/pi/.pi/agent/AGENTS.md' \
        '$DOTFILES/base/pi/.pi/agent/settings.json'"

# Regression guard for the "use <model>" false-positive bug.  Plain-text
# input switching was removed entirely in 3ebbb2e (Telegram bridge now strips
# the [telegram] prefix and pi handles /use as a slash command).  The only
# guard we still need: the old (?:^|\s) mid-sentence form must never reappear.
check_not "pi: model-switch has no mid-sentence (?:^|\s) anchor (false-positive source)" \
    '\(\?:\^\|\\s\)' "$DOTFILES/base/pi/.pi/agent/extensions/model-switch.ts"

# Regression guard for the guard layer itself. The unit tests verify that
# infra-safety + /check mode correctly classify mutations vs. reads when the
# shell arrives through the native tool (mutation-guard is now hypa-only).
check "pi: mutation-guard tests pass" \
    bash -c "cd '$DOTFILES/base/pi/.pi/agent/extensions' && node --experimental-strip-types --test lib/mutation-guard.test.ts"

# Free-tier model guard: OpenCode Go's free models are suffixed with -free and
# train on data. The shared-core Pi config must not route prompts or web-search
# summaries through them.
check "pi: no free-tier (-free) models in shared-core config" \
    bash -c "python3 -c \"
import json, sys

def bail_free(models, where):
    for m in models:
        if type(m) is str and m.endswith('-free'):
            sys.stderr.write('free-tier model in %s: %s\\n' % (where, m))
            sys.exit(1)

with open('$DOTFILES/base/pi/.pi/web-search.json') as f:
    ws = json.load(f)
bail_free([ws.get('summaryModel', '')], 'web-search.json:summaryModel')

with open('$DOTFILES/base/pi/.pi/agent/settings.json') as f:
    s = json.load(f)
bail_free([s.get('defaultModel', '')], 'settings.json:defaultModel')
bail_free(s.get('enabledModels', []), 'settings.json:enabledModels')
rl = s.get('rateLimitFallbacks', {})
bail_free(list(rl.keys()), 'settings.json:rateLimitFallbacks keys')
bail_free(list(rl.values()), 'settings.json:rateLimitFallbacks values')
\""


# =============================================================================
# 12. NEOVIM SMOKE TEST
# =============================================================================
section "Neovim smoke test"

if command -v nvim >/dev/null 2>&1; then
    # Parse-only check: verify all Lua config files have valid syntax.
    # This catches typos, wrong module names, and API breakage without
    # needing to bootstrap the full lazy.nvim plugin ecosystem.
    # A full startup test with plugins lives in the CI workflow.
    # -u NONE skips the user init.lua (may be Nix-managed/broken on a fresh
    # host and otherwise blocks headless startup on a "Press ENTER" prompt);
    # qa! force-quits past the "no write since last change" error.
    _nvim_lua_errors=0
    while IFS= read -r -d '' _f; do
        if ! nvim -u NONE --headless -c "luafile $_f" -c 'qa!' 2>/dev/null; then
            _nvim_lua_errors=$((_nvim_lua_errors + 1))
        fi
    done < <(find "$DOTFILES/base/nvim/.config/nvim/lua" -name '*.lua' -print0)

    if [[ $_nvim_lua_errors -eq 0 ]]; then
        _ok "nvim: all Lua config files parse without syntax errors"
    else
        _fail "nvim: $_nvim_lua_errors Lua config file(s) have syntax errors"
    fi

    _TS="$DOTFILES/base/nvim/.config/nvim/lua/plugins/treesitter.lua"
    # Assert against CODE only: strip `--` line comments first, so an
    # explanatory comment can't make a grep guard pass vacuously (the old
    # `defer_fn` guard once went green off the phrase "no vim.defer_fn" in a
    # comment after the real defer_fn was removed; the `nvim-treesitter%.configs`
    # guard was also blind — `%` is a Lua escape, but grep -E is ERE where `%`
    # is literal, so it could never match the real `nvim-treesitter.configs`).
    # v1.0 installs parsers via `setup { ensure_install = {...} }` (singular);
    # deferral is internal. ERE escapes: `\.` for a literal dot, `\b` word
    # boundary (`ensure_install\b` must NOT match the old `ensure_installed`).
    check "nvim: treesitter uses v1.0 ensure_install API" \
        bash -c "sed 's/--.*\$//' '$_TS' | grep -qE 'ensure_install\b'"
    check "nvim: treesitter does not use old ensure_installed key" \
        bash -c "! sed 's/--.*\$//' '$_TS' | grep -qE 'ensure_installed'"
    check "nvim: treesitter does not use old .configs module" \
        bash -c "! sed 's/--.*\$//' '$_TS' | grep -qE 'nvim-treesitter\.configs'"
    check "nvim: treesitter highlighting uses vim.treesitter.start" \
        bash -c "sed 's/--.*\$//' '$_TS' | grep -qE 'vim\.treesitter\.start'"
else
    _skip "nvim: config loads without errors" "nvim not installed"
fi


# =============================================================================
# SUMMARY
# =============================================================================
printf '\n%b%s%b\n' "$(_c "$BLD")" \
    "── Results ────────────────────────────────" "$(_c "$RST")"

printf '  %b✓%b %-3d passed\n'  "$(_c "$GRN")" "$(_c "$RST")" "$PASS"
printf '  %b✗%b %-3d failed\n'  "$(_c "$RED")" "$(_c "$RST")" "$FAIL"
[[ $SKIP -gt 0 ]] && \
printf '  %b○%b %-3d skipped\n' "$(_c "$YLW")" "$(_c "$RST")" "$SKIP"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    printf '\n%bFailed tests:%b\n' "$(_c "$BLD")" "$(_c "$RST")"
    for f in "${FAILED[@]}"; do
        printf '  %b✗%b %s\n' "$(_c "$RED")" "$(_c "$RST")" "$f"
    done
fi

echo ""
[[ $FAIL -eq 0 ]]
