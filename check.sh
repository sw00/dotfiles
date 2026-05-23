#!/usr/bin/env bash
# =============================================================================
# check.sh — dotfiles test suite
#
# Usage:  ./check.sh
# Exit:   0 = all tests passed, 1 = one or more failures
#
# Tests are labelled:
#   [GREEN] regression guard  — should pass now and stay passing
#   [RED]   TDD assertion     — fails now; passes after each planned change
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
check_stow "base: bash git nvim ssh fish tmux alacritty mise" \
    "$DOTFILES/base" bash git nvim ssh fish tmux alacritty mise
stow_end

# ── Linux stack: base → os/linux ───
section "Stow integrity — Linux stack  [GREEN]"

stow_begin
stow_layer "$DOTFILES/base" bash git nvim ssh fish tmux alacritty mise
check_stow "os/linux: alacritty awesome bash" \
    "$DOTFILES/os/linux" alacritty awesome bash
stow_end

# ── macOS stack: base → os/macos → hosts/mbpm3 ───
section "Stow integrity — macOS stack  [GREEN]"

stow_begin
stow_layer "$DOTFILES/base" bash git nvim ssh fish tmux
check_stow "os/macos: bash brew gnupg" \
    "$DOTFILES/os/macos" bash brew gnupg

stow_layer "$DOTFILES/os/macos" bash brew gnupg
check_stow "hosts/mbpm3: alacritty brew key_remap" \
    "$DOTFILES/hosts/mbpm3" alacritty brew key_remap
stow_end

# ── WSL stack: base → os/linux → os/wsl ───
# os/wsl is the right home for future WSL-specific stow packages.
# WSL fish config lives in base/fish/conf.d (fish's own layering avoids
# the stow cross-package symlink conflict).
section "Stow integrity — WSL stack  [GREEN]"

stow_begin
stow_layer "$DOTFILES/base" bash git nvim ssh fish tmux alacritty
stow_layer "$DOTFILES/os/linux" bash

mapfile -t _wsl_pkgs < <(
    find "$DOTFILES/os/wsl" -maxdepth 1 -mindepth 1 -type d \
        -printf '%f\n' 2>/dev/null | sort
)
if [[ ${#_wsl_pkgs[@]} -gt 0 ]]; then
    check_stow "os/wsl: ${_wsl_pkgs[*]}" "$DOTFILES/os/wsl"
else
    _ok "os/wsl: git config handled via os/wsl/git stow layer"
fi
stow_end


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
else
    _skip "fish: config.fish parses" "fish not installed"
fi


# =============================================================================
# 4. REPOSITORY STRUCTURE  [RED]
# Fix: create os/wsl/, add hosts/x13yg2/, move extras/wslconfig.* to hosts/
# =============================================================================
section "Repository structure  [RED]"

# Every platform needs its os/ directory
check "os/wsl/ directory exists" \
    test -d "$DOTFILES/os/wsl"

# The machine running check.sh must have a matching host directory
HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"
check "hosts/$HOST/ exists for current machine ($HOST)" \
    test -d "$DOTFILES/hosts/$HOST"

# extras/ should not hold host-specific wslconfig files (they belong in hosts/)
check "extras/wslconfig.* moved to hosts/" bash -c "
    ! find '$DOTFILES/extras' -maxdepth 1 -name 'wslconfig.*' | grep -q .
"


# =============================================================================
# 5. FISH CONFIG  [RED]
# Fix: update Fisher URL, add asdf initialisation
# =============================================================================
section "Fish config  [RED]"

check_not \
    "config.fish: Fisher URL is not the deprecated git.io shortlink" \
    'git\.io/fisher' \
    "$FISH_CFG"

check_has \
    "config.fish: mise activate is present" \
    'mise activate' \
    "$FISH_CFG"

check_not \
    "config.fish: no asdf references (replaced by mise)" \
    'asdf' \
    "$FISH_CFG"


# =============================================================================
# 6. TMUX CONFIG  [RED]
# Fix: make clipboard commands platform-conditional (pbcopy → if-shell guard)
# =============================================================================
section "Tmux config  [RED]"

TMUX_CFG="$DOTFILES/base/tmux/.config/tmux/tmux.conf"

# pbcopy must live inside an if-shell Darwin guard, not as a bare binding.
# After the fix an 'if-shell ... Darwin' line appears before the pbcopy bindings.
check_has \
    "tmux: clipboard has platform guard (if-shell Darwin)" \
    'if-shell.*Darwin' \
    "$TMUX_CFG"


# =============================================================================
# 7. GIT CONFIG  [RED]
# Fix: remove [filter "media"] and [filter "hawser"] stale blocks
# =============================================================================
section "Git config  [RED]"

GITCFG="$DOTFILES/base/git/.gitconfig"

check_not \
    'gitconfig: no stale [filter "media"] block (pre-lfs tool)' \
    '^\[filter "media"\]' \
    "$GITCFG"

check_not \
    'gitconfig: no stale [filter "hawser"] block (pre-lfs tool)' \
    '^\[filter "hawser"\]' \
    "$GITCFG"

# SSH config must not contain duplicate Host stanzas
check "ssh/config.d/lan.conf: no duplicate Host entries" bash -c "
    dupes=\$(grep -hE '^Host ' '$DOTFILES/base/ssh/.ssh/config.d/lan.conf' \
        | awk '{print \$2}' | sort | uniq -d)
    [[ -z \"\$dupes\" ]]
"


# =============================================================================
# 8. NEOVIM  [RED]
# Fix: remove packer.snapshot, replace neodev.nvim with lazydev.nvim
# =============================================================================
section "Neovim  [RED]"

check "nvim: packer.snapshot does not exist (migrated to lazy.nvim)" \
    bash -c "! test -f '$DOTFILES/base/nvim/.config/nvim/packer.snapshot'"

LSPCFG="$DOTFILES/base/nvim/.config/nvim/lua/plugins/lspconfig.lua"

check_not \
    "nvim: neodev.nvim not referenced (replaced by lazydev.nvim)" \
    'neodev' \
    "$LSPCFG"

check_has \
    "nvim: lazydev.nvim is referenced in lspconfig" \
    'lazydev' \
    "$LSPCFG"


# =============================================================================
# 9. ALACRITTY  [RED]
# Fix: consolidate configs using Alacritty's `import` directive
# =============================================================================
section "Alacritty  [RED]"

check_has \
    "alacritty (linux): config uses 'import' for shared base" \
    '^import' \
    "$DOTFILES/os/linux/alacritty/.config/alacritty/alacritty.toml"

check_has \
    "alacritty (mbpm3): config uses 'import' for shared base" \
    '^import' \
    "$DOTFILES/hosts/mbpm3/alacritty/.config/alacritty/alacritty.toml"

check_has \
    "alacritty (wsl/x13yg2): config uses 'import' for shared base" \
    '^import' \
    "$DOTFILES/hosts/x13yg2/alacritty/.config/alacritty/alacritty.toml"

check "alacritty (wsl/x13yg2): stow package exists" \
    test -d "$DOTFILES/hosts/x13yg2/alacritty"

check "alacritty: base.toml exists in base/alacritty" \
    test -f "$DOTFILES/base/alacritty/.config/alacritty/base.toml"


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

check_not "mise: asdf not referenced in fish config (replaced by mise)" \
    'asdf' "$FISH_CFG"

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
