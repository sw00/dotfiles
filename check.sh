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
check_stow "base: git nvim ssh fish tmux alacritty mise" \
    "$DOTFILES/base" git nvim ssh fish tmux alacritty mise
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
stow_layer "$DOTFILES/base" git nvim ssh fish tmux
check_stow "os/macos: bash brew gnupg" \
    "$DOTFILES/os/macos" bash brew gnupg

stow_layer "$DOTFILES/os/macos" bash brew gnupg
check_stow "hosts/mbpm3: alacritty brew fish key_remap mise" \
    "$DOTFILES/hosts/mbpm3" alacritty brew fish key_remap mise
stow_end

# ── WSL stack: base → os/linux → os/wsl ───
# os/wsl/windows/ holds content for the Windows side (pushed by up.sh, not stowed).
# Only os/wsl/git/ is a stow package; bootstrap.sh lists it explicitly.
section "Stow integrity — WSL stack  [GREEN]"

stow_begin
stow_layer "$DOTFILES/base" git nvim ssh fish tmux alacritty
stow_layer "$DOTFILES/os/linux" bash
check_stow "os/wsl: git gnupg" "$DOTFILES/os/wsl" git gnupg
stow_end

check "os/wsl/up.sh exists" \
    test -f "$DOTFILES/os/wsl/up.sh"

check "os/wsl/gnupg: pinentry-wsl.sh exists" \
    test -f "$DOTFILES/os/wsl/gnupg/.gnupg/pinentry-wsl.sh"

check "os/wsl/gnupg: pinentry-wsl.sh is executable" \
    test -x "$DOTFILES/os/wsl/gnupg/.gnupg/pinentry-wsl.sh"

check "os/wsl/windows/wsl.conf exists" \
    test -f "$DOTFILES/os/wsl/windows/wsl.conf"

check_has "bootstrap: WSL calls os/wsl/up.sh" \
    'os/wsl/up.sh' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: os/wsl stow is explicit (git gnupg)" \
    'stow_dir.*os/wsl.*git' "$DOTFILES/bootstrap.sh"

# hosts/x13yg2: only alacritty/ should be a stow package (vscodium/ and wsl/ removed)
check "hosts/x13yg2: vscodium/ not present (moved to os/wsl/windows/)" \
    bash -c "! test -d '$DOTFILES/hosts/x13yg2/vscodium'"

check "hosts/x13yg2: wsl/ not present (script moved to os/wsl/up.sh)" \
    bash -c "! test -d '$DOTFILES/hosts/x13yg2/wsl'"


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

# extras/ should not hold host-specific wslconfig files (they belong in hosts/)
check "extras/wslconfig.* moved to hosts/" bash -c "
    ! find '$DOTFILES/extras' -maxdepth 1 -name 'wslconfig.*' | grep -q .
"


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

check_not \
    "config.fish: no asdf references (replaced by mise)" \
    'asdf' \
    "$FISH_CFG"


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
# 8. NEOVIM
# =============================================================================
section "Neovim  [GREEN]"

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
    "alacritty (wsl/x13yg2): config uses 'import' for shared base" \
    '^import' \
    "$DOTFILES/hosts/x13yg2/alacritty/.config/alacritty/alacritty.toml"

check "alacritty (wsl/x13yg2): stow package exists" \
    test -d "$DOTFILES/hosts/x13yg2/alacritty"

check "komorebi: default config exists in os/wsl/windows" \
    test -f "$DOTFILES/os/wsl/windows/komorebi/config.json"

check "komorebi (wsl/x13yg2): host config exists" \
    test -f "$DOTFILES/hosts/x13yg2/komorebi/.config/komorebi/config.json"

check "komorebi: default whkdrc exists in os/wsl/windows" \
    test -f "$DOTFILES/os/wsl/windows/komorebi/whkdrc"

check "komorebi (wsl/x13yg2): host whkdrc exists" \
    test -f "$DOTFILES/hosts/x13yg2/komorebi/.config/komorebi/whkdrc"

check_has "up.sh: komorebi config installation present" \
    'KOMOREBI' "$DOTFILES/os/wsl/up.sh"

check_has "up.sh: whkdrc installation present" \
    'whkdrc' "$DOTFILES/os/wsl/up.sh"

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

check_has "mise: tmux is managed by mise (not apt/brew)" \
    '^tmux ' "$MISE_CFG"

check_has "bootstrap: sesh installed via ensure_sesh" \
    'ensure_sesh' "$DOTFILES/bootstrap.sh"

check_has "mise: devops tools declared (kubectl, helm, k9s)" \
    'kubectl' "$MISE_CFG"

check_has "mise: mise itself in macOS Brewfile-base (Homebrew install beats curl on macOS)" \
    'brew "mise"' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_not "mise: neovim not in macOS Brewfile-base (managed by mise)" \
    'brew "neovim"' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_not "Brewfile-host: no stale asdf entry" \
    'brew "asdf"' "$DOTFILES/hosts/mbpm3/brew/.Brewfile-host"

check_not "Brewfile-host: fzf removed (managed by mise)" \
    'brew "fzf"' "$DOTFILES/hosts/mbpm3/brew/.Brewfile-host"

check_not "Brewfile-host: numpy removed (not a system package)" \
    'brew "numpy"' "$DOTFILES/hosts/mbpm3/brew/.Brewfile-host"

check_not "Brewfile-host: pytorch removed (not a system package)" \
    'brew "pytorch"' "$DOTFILES/hosts/mbpm3/brew/.Brewfile-host"

check "bootstrap: macOS calls ensure_homebrew_bundle" \
    grep -q 'ensure_homebrew_bundle' "$DOTFILES/bootstrap.sh"

check "os/wsl/windows/winget.txt exists" \
    test -f "$DOTFILES/os/wsl/windows/winget.txt"

check_has "winget.txt: Alacritty entry present" \
    'Alacritty.Alacritty' "$DOTFILES/os/wsl/windows/winget.txt"

check_has "winget.txt: VSCodium entry present" \
    'VSCodium.VSCodium' "$DOTFILES/os/wsl/windows/winget.txt"

check_not "bootstrap: tmux not in ensure_system_tools (managed by mise)" \
    'wanted.*tmux\|tmux.*wanted' "$DOTFILES/bootstrap.sh"

check_not "fish/config.fish: psh abbr not present (WSL-only, lives in wsl.fish)" \
    'abbr.*psh' "$FISH_CFG"

check_not "bootstrap: gnupg not in base stow (stowed per-OS to avoid conflict)" \
    'stow_dir.*base.*gnupg' \
    "$DOTFILES/bootstrap.sh"

check_has "bootstrap: WSL stows os/wsl gnupg (pinentry-wsl)" \
    'stow_dir.*os/wsl.*gnupg' \
    "$DOTFILES/bootstrap.sh"

check_has "os/macos/gpg-agent.conf: complete config (pinentry + TTL)" \
    'default-cache-ttl' \
    "$DOTFILES/os/macos/gnupg/.gnupg/gpg-agent.conf"

check "base/gnupg removed (conflict source)" \
    bash -c "! test -d '$DOTFILES/base/gnupg'"

check_has "bootstrap: git-crypt lock guard present" \
    '_repo_is_locked' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: lf in ensure_system_tools" \
    'wanted=.*lf' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: tig in ensure_system_tools" \
    'wanted=.*tig' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: pinentry-gtk2 in WSL system tools" \
    'pinentry-gtk2' "$DOTFILES/bootstrap.sh"

check_has "up.sh: gpg-agent reload present" \
    'gpg-connect-agent reloadagent' "$DOTFILES/os/wsl/up.sh"

# gpg-agent does not expand ~ in pinentry-program, so up.sh must write
# gpg-agent.conf with $HOME expanded — not stow-managed.
check "os/wsl/gnupg: gpg-agent.conf NOT stow-managed (written by up.sh)" \
    bash -c "! test -f '$DOTFILES/os/wsl/gnupg/.gnupg/gpg-agent.conf'"

check_has "up.sh: gpg-agent.conf written with absolute pinentry-wsl path" \
    'pinentry-program.*HOME.*pinentry-wsl' "$DOTFILES/os/wsl/up.sh"

check_has "Brewfile-host: lf present" \
    'brew "lf"' "$DOTFILES/hosts/mbpm3/brew/.Brewfile-host"

check_has "Brewfile-host: tig present" \
    'brew "tig"' "$DOTFILES/hosts/mbpm3/brew/.Brewfile-host"

check_has "mise: shellcheck declared" \
    'shellcheck' "$MISE_CFG"

check_not "mise: experimental flag removed" \
    '^experimental' "$MISE_CFG"

check_not "fish/conf.d/git.fish: no legacy omf hooks" \
    'functions -e _git_install' \
    "$DOTFILES/base/fish/.config/fish/conf.d/git.fish"

# ── Tools / desktop audit ───────────────────────────────────────────────────────────
check_not "mise: work-specific tools not in global config" \
    'kubeseal\|kustomize\|argocd\|opentofu\|^helm' "$MISE_CFG"

check "hosts/mbpm3: work mise tools declared" \
    test -f "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check_has "hosts/mbpm3: mise work tools include helm" \
    'helm' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check_not "Brewfile-base: homeport tap removed" \
    'homeport' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_not "Brewfile-host: homeport tap removed" \
    'homeport' "$DOTFILES/hosts/mbpm3/brew/.Brewfile-host"

check_not "Brewfile-host: monokle removed" \
    'monokle' "$DOTFILES/hosts/mbpm3/brew/.Brewfile-host"

check_has "hosts/mbpm3: stern in work mise tools (was asdf)" \
    'stern' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check_has "hosts/mbpm3: k3d in work mise tools (was asdf)" \
    'k3d' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check_has "hosts/mbpm3: awscli in work mise tools (was asdf)" \
    'awscli' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check_not "Brewfile-host: asdf removed (replaced by mise)" \
    'brew "asdf"' "$DOTFILES/hosts/mbpm3/brew/.Brewfile-host"

check_has "bootstrap: stow_dir handles unowned dir symlinks (asdf→mise migration)" \
    'existing target is not owned by stow' "$DOTFILES/bootstrap.sh"

check_has "Brewfile-base: obsidian present" \
    'obsidian' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "Brewfile-base: flameshot present" \
    'flameshot' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_not "Brewfile-host: flameshot removed (moved to base)" \
    'flameshot' "$DOTFILES/hosts/mbpm3/brew/.Brewfile-host"

check_not "fish/config.fish: flyl removed (host-specific, in hosts/mbpm3)" \
    'flyl' "$DOTFILES/base/fish/.config/fish/config.fish"

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
# 11. NEOVIM SMOKE TEST
# =============================================================================
section "Neovim smoke test"

if command -v nvim >/dev/null 2>&1; then
    # Parse-only check: verify all Lua config files have valid syntax.
    # This catches typos, wrong module names, and API breakage without
    # needing to bootstrap the full lazy.nvim plugin ecosystem.
    # A full startup test with plugins lives in the CI workflow.
    _nvim_lua_errors=0
    while IFS= read -r -d '' _f; do
        if ! nvim --headless -c "luafile $_f" -c 'qa' 2>/dev/null; then
            _nvim_lua_errors=$((_nvim_lua_errors + 1))
        fi
    done < <(find "$DOTFILES/base/nvim/.config/nvim/lua" -name '*.lua' -print0)

    if [[ $_nvim_lua_errors -eq 0 ]]; then
        _ok "nvim: all Lua config files parse without syntax errors"
    else
        _fail "nvim: $_nvim_lua_errors Lua config file(s) have syntax errors"
    fi

    check_has "nvim: treesitter uses v1 API (no nvim-treesitter.configs)" \
        'nvim-treesitter'\'').install' "$DOTFILES/base/nvim/.config/nvim/lua/plugins/treesitter.lua"

    check_not "nvim: treesitter does not use old .configs module" \
        'nvim-treesitter%.configs' "$DOTFILES/base/nvim/.config/nvim/lua/plugins/treesitter.lua"

    check_has "nvim: treesitter install() is deferred (non-blocking)" \
        'defer_fn' "$DOTFILES/base/nvim/.config/nvim/lua/plugins/treesitter.lua"

    check_has "nvim: treesitter highlighting uses vim.treesitter.start" \
        'vim.treesitter.start' "$DOTFILES/base/nvim/.config/nvim/lua/plugins/treesitter.lua"
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
