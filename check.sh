#!/usr/bin/env bash
# =============================================================================
# check.sh — dotfiles test suite
#
# Usage:  ./check.sh
# Exit:   0 = all tests passed, 1 = one or more failures
#
# A full run is FAST: measured 15.8-16.6s for 514 assertions on mbpm3 (2026-10-20).
# The biggest single section is the pwt harness at ~9s; nothing else exceeds 2s. This
# header used to claim "~5 minutes", and that stale number cost real time — a session
# slept 300s per run instead of polling. Do not assume a duration: run it in the
# foreground, or poll for the "── Results" line.
#
# While iterating on one behavioural block, extract it into a scratch script with a
# `check()` stub instead of re-running everything:
#   sed -n '/<start marker>/,/<end marker>/p' check.sh > /tmp/block.sh
# That turns the loop into seconds, and a block that hangs shows up as a hang in one
# place rather than as a suite that "took longer than usual". A filtered or extracted
# run is NEVER a gate: only a full run's pass count means anything (a harness bug once
# hid skipped tests behind a green summary).
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

# Pass if an ERE pattern IS found in a file.
# The `--` is load-bearing: without it a pattern beginning with "-" (e.g.
# '--session-id "…"') is parsed as a grep OPTION, grep errors, and 2>/dev/null
# turns that into a silent failure that looks like a genuine mismatch.
check_has() {
    local name="$1" pattern="$2" file="$3"
    if grep -qE -- "$pattern" "$file" 2>/dev/null; then _ok "$name"; else _fail "$name"; fi
}

# Pass if an ERE pattern is NOT found in a file. (`--` as in check_has.)
check_not() {
    local name="$1" pattern="$2" file="$3"
    if ! grep -qE -- "$pattern" "$file" 2>/dev/null; then _ok "$name"; else _fail "$name"; fi
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

# Fixtures that make commits must disable signing. With a locked GPG agent the suite
# would sit at a pinentry prompt instead of failing, and nothing would say why — the
# failure mode is a run that never finishes. Every fixture here passes
# `-c commit.gpgsign=false`; this keeps it that way. The pattern spells the space as a
# class so this line cannot match itself.
check_not "check.sh: fixture commits never sign (a locked agent hangs the suite)" \
    'git[ ]commit' "$DOTFILES/check.sh"

mapfile -t ALL_SCRIPTS < <(
    find "$DOTFILES" \
        -not -path '*/.git/*' \
        -not -path '*/tmux/plugins/*' \
        -not -path '*/secrets/*' \
        \( -name '*.sh' -o -name '*.bash' \) \
        -type f | sort
)

# Lint repo content, not whatever happens to be lying in the working tree: a
# scratch clone under $DOTFILES (an ignored src/, say) is not part of the repo,
# and CI — which runs this suite on a fresh clone — never sees it.  Only the
# repo rooted at $DOTFILES counts (an enclosing repo's rules must not decide
# what this suite lints), untracked-but-not-ignored scripts are still linted so
# a new script is checked before it is committed, and an empty result is fatal
# rather than a silent green run.
if [[ "$(git -C "$DOTFILES" rev-parse --show-toplevel 2>/dev/null)" == "$(realpath "$DOTFILES")" ]]; then
    _lintable=()
    for s in "${ALL_SCRIPTS[@]}"; do
        git -C "$DOTFILES" check-ignore -q -- "$s" || _lintable+=("$s")
    done
    ALL_SCRIPTS=("${_lintable[@]}")
fi

# Unconditional on purpose: without a repo the list falls back to the bare find,
# where an empty result means the same thing — stop rather than report a green
# run that linted nothing.
if [[ ${#ALL_SCRIPTS[@]} -eq 0 ]]; then
    printf '==> check.sh: no lintable scripts under %s — wrong DOTFILES?\n' "$DOTFILES" >&2
    exit 1
fi

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

# Node --experimental-strip-types needs a build compiled with TypeScript
# support (always present on v23+; absent on many v22 builds). Probe with a
# trivial .ts load rather than a version string, so the guard tracks the
# actual capability.
_CAN_STRIP_TS=0
if command -v node >/dev/null 2>&1; then
    _ts_probe_dir=$(mktemp -d)
    printf 'const _x: number = 1\n' > "$_ts_probe_dir/probe.ts"
    if node --experimental-strip-types "$_ts_probe_dir/probe.ts" >/dev/null 2>&1; then
        _CAN_STRIP_TS=1
    fi
    rm -rf "$_ts_probe_dir"
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
check_stow "base: git nvim ssh fish tmux alacritty mise pi sesh tokentelemetry claude" \
    "$DOTFILES/base" git nvim ssh fish tmux alacritty mise pi sesh claude
stow_end

# Claude Code's defaults are the origin of the "🤖 Generated with [Claude Code]"
# PR footer and the `Co-Authored-By: <model>` commit trailer. Both are hidden by
# empty strings here; the object form is deliberate — `"attribution": false`
# hides the same things but older releases reject the whole settings file that
# holds it (docs: v2.1.281+), and this file is stowed to every host.
check_has "claude: PR footer attribution disabled" \
    '"pr": ""' "$DOTFILES/base/claude/.claude/settings.json"
check_has "claude: commit trailer attribution disabled" \
    '"commit": ""' "$DOTFILES/base/claude/.claude/settings.json"
check_has "claude: cloud/Remote-Control session URL omitted" \
    '"sessionUrl": false' "$DOTFILES/base/claude/.claude/settings.json"
check_has "bootstrap: base stow list includes claude" \
    'stow_dir.*DOTFILES/base.*claude' "$DOTFILES/bootstrap.sh"

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
# The update path on every machine is "run bootstrap": so it must RESTOW (a file
# added to a package is otherwise never linked) and dry-run first (an existing target
# is then reported instead of leaving a half-applied layer). Both were load-bearing
# the week pwt added a completion and a bin script to already-stowed packages.
check_has "bootstrap: stows with --restow, so new package files get linked" \
    'stow --restow --no-folding' "$DOTFILES/bootstrap.sh"
check_has "bootstrap: dry-runs stow to catch conflicts before touching \$HOME" \
    'stow -n --no-folding' "$DOTFILES/bootstrap.sh"

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

# tmux: start a server against the config in an isolated socket, then kill it.
# Parse with both the PATH tmux and (when present) the system tmux — WSL's apt
# tmux 3.4 predates extended-keys-format, so the config must stay valid there.
# Cleanup uses the same binary that started the server (client/server protocol
# versions must match, or kill-server silently fails and strands the socket).
for _tm in tmux /usr/bin/tmux; do
    if command -v "$_tm" >/dev/null 2>&1; then
        _label="$_tm"
        [ "$_tm" = tmux ] && _label="tmux (PATH)"
        check "tmux: config parses without errors [$_label]" bash -c "
            '$_tm' -L dotfiles_check \
                 -f '$DOTFILES/base/tmux/.config/tmux/tmux.conf' \
                 start-server 2>/dev/null
            rc=\$?
            '$_tm' -L dotfiles_check kill-server 2>/dev/null || true
            exit \$rc
        "
    fi
done
unset _tm _label

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
# ── dangling stow links ──────────────────────────────────────────────────────
# stow cannot unstow a symlink whose target was deleted from its package, so a
# removed dotfile strands a dangling link in $HOME — and a dangling plugin
# symlink breaks lazy.nvim on every nvim start. bootstrap prunes these; this
# asserts the machine is clean. Machine-only: CI has no stowed $HOME.
section "Dangling stow links"

if [[ -n "${CI:-}" ]]; then
    _skip "no dangling symlinks into the repo" "CI environment"
else
    _dangling=0
    for _root in "$HOME/.config" "$HOME/bin" "$HOME/.local/bin" "$HOME/.ssh"; do
        [[ -d "$_root" ]] || continue
        while IFS= read -r _l; do
            # Portable dangling test: macOS find has no -xtype (and with stderr
            # discarded it silently matches nothing, i.e. a false negative).
            [[ -L "$_l" && ! -e "$_l" ]] || continue
            _t="$(readlink "$_l")" || continue
            _dir="$(cd "$(dirname "$_l")" 2>/dev/null && cd "$(dirname "$_t")" 2>/dev/null && pwd)" || continue
            if [[ "$_dir" == "$DOTFILES"/* ]]; then
                _dangling=$((_dangling + 1))
                printf '      %s -> %s\n' "${_l#"$HOME"/}" "$_t"
            fi
        done < <(find "$_root" -type l 2>/dev/null)
    done
    if [[ $_dangling -eq 0 ]]; then
        _ok "no dangling symlinks into the repo"
    else
        _fail "no dangling symlinks into the repo ($_dangling found — bootstrap prunes these)"
    fi
fi

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

check_has \
    "ssh-agent.fish: started agent is disowned so fish does not warn on exit" \
    'disown' \
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

# Tombstone: extended-keys-format only exists in tmux >= 3.5 (WSL's apt tmux
# 3.4 predates it). It was removed in 5f629b2 ("fix(tmux): invalid option") and
# re-added bare in cff3f3a — twice bitten. The set must stay gated behind the
# option-table probe: no bare set, probe present.
check_not "tmux: extended-keys-format NOT set bare (must be version-gated)" \
    '^set -g extended-keys-format' \
    "$TMUX_CFG"
check_has "tmux: extended-keys-format gated behind option probe (>= 3.5)" \
    'show-options -s extended-keys-format' \
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

# navi cannot come from mise on macOS: aqua:denisidoro/navi publishes linux and
# windows/amd64 only, so `mise install navi` fails outright on Apple Silicon. That
# is why it sat declared-but-missing for so long. It now carries the same os
# restriction as btop, and brew owns it on macOS.
check_has "mise: navi declared with an os restriction (aqua is linux/windows only)" \
    '^\[tools\.navi\]' "$MISE_CFG"

check_has "Brewfile-base: navi present (no aqua build for macOS)" \
    'brew "navi"' "$DOTFILES/os/macos/brew/.Brewfile-base"

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

# Reverse guards for the privileged-gate refactor (cf09392): bootstrap now owns
# wsl.conf and the WSL gpg-agent.conf in _ensure_wsl_conf / _ensure_wsl_gpg;
# up.sh must stay root-free. These are NOT migration tombstones — they prevent
# future edits from slipping sudo or a privileged gpg-agent write back into
# up.sh. (Stripped once by a7c953c's "strip tombstones" pass; restored.)
check_not "up.sh: contains no sudo (wsl.conf moved to bootstrap privileged gate)" \
    '\bsudo\b' "$DOTFILES/os/wsl/up.sh"
check_not "up.sh: no WSL gpg-agent.conf pinentry-wsl write (moved to bootstrap _ensure_wsl_gpg)" \
    'pinentry-program.*pinentry-wsl' "$DOTFILES/os/wsl/up.sh"

# Tombstone: 31cf793 stripped `local` from up.sh's top-level declarations but
# left the bare declaration lines (winget_ver, major minor, out, pkg) behind.
# bash executes those as commands and `set -e` aborts up.sh mid-run; shellcheck
# does not flag bare words (they look like command invocations), so guard
# explicitly: any line of bare identifier(s) in up.sh must be a shell keyword.
# awk skips heredoc bodies so embedded content (e.g. python's `import sys`,
# `EOF`/`PYEOF` terminators) can't false-positive.
check "up.sh: no bare-word leftovers (stripped-local tombstone)" bash -c "
    awk '
        /<<[[:space:]]+.(EOF|PYEOF)./ { in_hd=1; next }
        in_hd && /^(EOF|PYEOF)[[:space:]]*$/ { in_hd=0; next }
        !in_hd && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*([[:space:]]+[A-Za-z_][A-Za-z0-9_]*)*[[:space:]]*$/ { print NR\": \"\$0 }
    ' '$DOTFILES/os/wsl/up.sh' \
    | grep -vE ':[[:space:]]*(fi|done|else|do|then|esac|in|;;|break|continue|return|exit)[[:space:]]*$' \
    | grep -q . && exit 1 || exit 0
"

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

# tig is kept as a fallback git-history browser, so this asserts presence, not
# absence. The pattern matches both the wanted=(...) initialiser and a
# wanted+=(tig) append, which is how the per-platform branch adds packages.
check_has "bootstrap: tig in _install_system_packages (merged prereqs + system tools)" \
    'wanted\+?=.*tig' "$DOTFILES/bootstrap.sh"

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
    'kubeseal\|kustomize\|argocd\|opentofu\|^helm\|crane' "$MISE_CFG"

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

check_has "hosts/mbpm3: crane in work mise tools" \
    'crane' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check_has "bootstrap: stow_dir handles unowned dir symlinks (asdf→mise migration)" \
    'existing target is not owned by stow' "$DOTFILES/bootstrap.sh"



check_has "Brewfile-base: tig present (moved from host)" \
    'brew "tig"' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "Brewfile-base: graphviz present (moved from host)" \
    'brew "graphviz"' "$DOTFILES/os/macos/brew/.Brewfile-base"

# Declared for gmake, not make: the brew formula is keg-only for `make`, so
# /usr/bin/make still wins and only `gmake` is reachable from it.
check_has "Brewfile-base: make present (provides gmake; macOS make is 3.81)" \
    'brew "make"' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "Brewfile-base: obsidian present" \
    'obsidian' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "Brewfile-base: flameshot present" \
    'flameshot' "$DOTFILES/os/macos/brew/.Brewfile-base"

# Rev 4: the mbpm3 work.fish conf.d fragment was deleted — it carried a work
# target abbreviation in cleartext. Work tooling stays mbpm3-exclusive (see the
# mise tests above); what replaced it stores no identifier at all, discovering
# its targets from the tools' own config at runtime.
check "hosts/mbpm3: work conf.d fragment removed (target names must not be public)" \
    bash -c "! test -e '$DOTFILES/hosts/mbpm3/fish/.config/fish/conf.d/work.fish'"

for _wf in work-login work-status; do
    check "hosts/mbpm3: $_wf function present" \
        test -f "$DOTFILES/hosts/mbpm3/fish/.config/fish/functions/$_wf.fish"

    check "hosts/mbpm3: $_wf parses" \
        fish -n "$DOTFILES/hosts/mbpm3/fish/.config/fish/functions/$_wf.fish"
done

# The probe helpers must be their OWN files. fish autoloads a function only from
# a file NAMED after it, so while these lived inside work-status.fish, work-login
# called them as unknown commands in any shell where work-status had not run —
# and because work-login's gates treat an empty probe as "nothing to do", it
# reported success while probing nothing (user hit this 2026-10-20). `functions -q`
# triggers the same autoload path a call would, without running anything.
_work_fn_dir="$DOTFILES/hosts/mbpm3/fish/.config/fish/functions"
for _wf in __work_aws_sso_profile __work_fly_targets __work_exec_contexts; do
    check "hosts/mbpm3: $_wf has its own file" \
        test -f "$_work_fn_dir/$_wf.fish"

    check "hosts/mbpm3: $_wf parses" \
        fish -n "$_work_fn_dir/$_wf.fish"

    check "hosts/mbpm3: $_wf autoloads in a fresh fish" \
        fish -N -c "set fish_function_path '$_work_fn_dir'; functions -q $_wf"
done

# Rev 5: az joined the work toolchain. Assert the wiring rather than just the
# presence of the word, so the two functions cannot drift apart: work-login must
# offer az by default, and both must probe it the same way — otherwise one
# reports ready while the other re-logs in on every run.
check "hosts/mbpm3: work-login defaults include az" \
    grep -q 'set want aws az k8s argocd fly' "$DOTFILES/hosts/mbpm3/fish/.config/fish/functions/work-login.fish"

check "hosts/mbpm3: work-login has an az case" \
    grep -qE '^[[:space:]]+case az$' "$DOTFILES/hosts/mbpm3/fish/.config/fish/functions/work-login.fish"

check "hosts/mbpm3: work-login probes az with account show" \
    grep -q 'az account show' "$DOTFILES/hosts/mbpm3/fish/.config/fish/functions/work-login.fish"

check "hosts/mbpm3: work-status probes az with account show" \
    grep -q 'az account show' "$DOTFILES/hosts/mbpm3/fish/.config/fish/functions/work-status.fish"

# Shape-level leak scan over every tracked file outside secrets/. The pattern is
# written with bracket classes so this file does not contain the contiguous
# shapes it searches for — otherwise it would match its own pattern list. That
# discipline is not cosmetic: the pre-commit hook uses the SAME stems, so
# spelling one out here — even inside a comment — is blocked by the guard that
# reads it. The self-immunity test below locks this in.
# Catches SHAPES: a cloud SSO start URL, an EKS endpoint, an AKS/ARO host, an
# account-id key, a JWT. Employer *names* are not sensitive; infrastructure
# resource names, IDs and URLs/IPs are, and those live in secrets/leak-patterns.
#
# `--cached`, never the worktree: git-crypt paths are DECRYPTED on disk, so a
# worktree scan reads plaintext that is not published and reports encrypted
# content as a leak (it flagged base/ssh/.ssh/config.d/work.conf, whose every
# blob has been ciphertext since 2025). Index content is what gets pushed.
_leak_shapes='awsapps[.]com|eks[.]amazonaws[.]com|ar[o]app[.]io|sso_(start_url|account_id)|e[y]J'
check "leak scan: no cloud/SSO identifiers tracked outside secrets/" \
    bash -c "! git -C '$DOTFILES' grep --cached -IE '$_leak_shapes' -- ':(exclude)secrets/**'"

check "leak scan: the guard's own files are immune to its shape list" \
    bash -c "! grep -aqE '$_leak_shapes' '$DOTFILES/check.sh' '$DOTFILES/.githooks/pre-commit'"

# ── Leak guard: the whole published tree (the backstop the hook cannot be) ──
# The pre-commit hook only sees lines a commit ADDS, so an identifier that
# predates its stem — or a commit made with --no-verify — is invisible to it.
# CI cannot take over: it checks out a LOCKED clone and cannot read the stems at
# all. This runs the identifier scan over the whole index, which is exactly the
# set of bytes that gets pushed, and says so out loud when it cannot run.
if head -c 10 "$DOTFILES/secrets/leak-patterns" 2>/dev/null | grep -aq GITCRYPT; then
    _skip "leak scan: no identifier stems in published content" \
        "locked clone (CI has no git-crypt key)"
else
    _stem_re="$(grep -vE '^[[:space:]]*(#|$)' "$DOTFILES/secrets/leak-patterns" | paste -sd'|' -)"
    _stem_hits="$(git -C "$DOTFILES" grep --cached -lIE "$_stem_re" -- ':(exclude)secrets/**' || true)"
    # Prints offending PATHS only — never the matched text, which is the secret.
    [[ -n "$_stem_hits" ]] && printf '      %s\n' $_stem_hits
    check "leak scan: no identifier stems in published content" test -z "$_stem_hits"
fi

# ── Leak guard: the pre-commit hook ─────────────────────────────────────────
# CI cannot run the identifier scan (locked clone, no key), so that half of the
# guard has to live in a local hook. Assert it exists AND that bootstrap wires it.
check "hooks: .githooks/pre-commit present" \
    test -f "$DOTFILES/.githooks/pre-commit"

check "hooks: .githooks/pre-commit executable" \
    test -x "$DOTFILES/.githooks/pre-commit"

check_has "bootstrap: wires core.hooksPath to .githooks" \
    'core.hooksPath .githooks' "$DOTFILES/bootstrap.sh"

check_has "hook: blocks a plaintext file staged under secrets/" \
    'staged as PLAINTEXT' "$DOTFILES/.githooks/pre-commit"

check_has "hook: asserts git-crypt filter coverage per staged path" \
    'git check-attr filter' "$DOTFILES/.githooks/pre-commit"

check_has "hook: never reports green when the pattern file is locked" \
    'is locked' "$DOTFILES/.githooks/pre-commit"

check "leak-patterns: git-crypt filter applies (asserted without reading it)" \
    bash -c "git -C '$DOTFILES' check-attr filter secrets/leak-patterns | grep -q git-crypt"

# Every path a .gitattributes rule routes through git-crypt must really hold
# ciphertext in HEAD. This is the CI-side half of the hook's encryption check:
# the hook only ever samples what a commit touches, so a path that slipped a
# `**/...` rule keeps publishing plaintext forever and no commit re-checks it.
_cipher_not=""
while IFS= read -r _p; do
    [[ "$(git -C "$DOTFILES" check-attr filter -- "$_p" | awk '{print $NF}')" == git-crypt ]] || continue
    git -C "$DOTFILES" cat-file blob "HEAD:$_p" 2>/dev/null | head -c 10 | grep -aq GITCRYPT \
        || _cipher_not="$_cipher_not $_p"
done < <(git -C "$DOTFILES" ls-files)
[[ -n "$_cipher_not" ]] && printf '      not encrypted in HEAD:%s\n' "$_cipher_not"
check "git-crypt: every filtered path is ciphertext in HEAD" test -z "$_cipher_not"

# fly refuses to talk to a mismatched server API, so its version must be pinned
# rather than floated on mise's `latest`.
check_has "hosts/mbpm3: fly pinned to the server API version" \
    '^fly[[:space:]]*= "8\.3\.0"' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

check_not "hosts/mbpm3: fly not floating on latest" \
    '^fly[[:space:]]*= "latest"' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

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

# ── Ownership drift guards ───────────────────────────────────────────────────
# The audit behind these found (a) tools installed with no declaration in any
# config and (b) five tools installed by brew AND mise at once, every one of them
# silently resolving to brew. Neither class was visible to this suite: the parity
# tests above only ever covered three hardcoded packages. These generalise it —
# the same reasoning as the leak guard, applied to package ownership.
BREW_HOST="$DOTFILES/hosts/$HOST/brew/.Brewfile-host"
MISE_HOST="$DOTFILES/hosts/$HOST/mise/.mise.toml"

# Every formula named in either Brewfile that applies to this host.
_brew_declared() {
    cat "$BREW_BASE" "$BREW_HOST" 2>/dev/null \
        | grep -oE '^brew "[^"]+"' | cut -d'"' -f2 | sort -u
}

# Does either mise config declare this tool? BOTH forms count: the key form
# (`foo = "1.0"`) and the table form (`[tools.foo]`) that btop and navi use when
# they need an os restriction. Missing the table form was a real blind spot when
# this guard shipped — the btop/navi exemptions masked it, so a genuine dual
# owner would have passed silently.
_mise_declares() {
    grep -qE "^\[tools\.\"?$1\"?\][[:space:]]*$|^\"?$1\"?[[:space:]]*=" \
        "$MISE_CFG" "$MISE_HOST" 2>/dev/null
}

# (b) One owner per tool: a name may not be both a mise-declared tool and a
# Brewfile formula. Pure config, so it also runs in CI. The exceptions are a
# documented platform split — aqua publishes no macOS build, so mise carries the
# linux declaration and brew carries macOS.
_dual_exempt='btop navi'
_both_owned=""
while read -r _f; do
    [ -n "$_f" ] || continue
    case " $_dual_exempt " in *" $_f "*) continue ;; esac
    if _mise_declares "$_f"; then
        _both_owned+="$_f "
    fi
done < <(_brew_declared)
if [ -n "$_both_owned" ]; then
    _fail "ownership: declared by both mise and brew — $_both_owned"
else
    _ok "ownership: no tool declared by both mise and brew"
fi

# Self-tests for the matcher above: both declaration forms must be recognised, or
# the guard silently misses exactly what it exists for.
check "guard: recognises the table-form declaration (btop)" _mise_declares btop
check "guard: recognises the key-form declaration (kubectl)" _mise_declares kubectl
check "guard: does not claim an undeclared tool" \
    test -z "$(_mise_declares definitely-not-a-tool && echo yes)"

# (a) Every explicitly installed formula must be either declared in a Brewfile or
# exempted here with a reason. Needs this machine's brew state, so it skips on the
# ubuntu CI runner rather than pretending to be green.
declare -A _brew_exempt=(
    [localstack/tap/localstack-cli]="LocalStack CLI; installed once, left unmanaged"
    [tmux-fingers]="tap formula; TPM is the plugin path"
)
if command -v brew >/dev/null 2>&1; then
    _decl=$(_brew_declared)
    _undecl=""
    while read -r _f; do
        [ -n "$_f" ] || continue
        [ -n "${_brew_exempt[$_f]+x}" ] && continue
        printf '%s\n' "$_decl" | grep -qxF "$_f" && continue
        _undecl+="$_f "
    done < <(brew leaves 2>/dev/null)
    if [ -n "$_undecl" ]; then
        _fail "brew: installed but declared nowhere and not exempt — $_undecl"
    else
        _ok "brew: every explicitly installed formula is declared or exempt"
    fi
else
    _skip "brew: every explicitly installed formula is declared or exempt" "brew not installed (CI)"
fi

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
    bash -c "! grep -rEq 'telegram|agentbox|tg-status|tg-session|confirmation-gate|cf-gateway|pi-telegram|ELEVATE|READ/ASK/DEFER' \
        '$DOTFILES/base/pi/.pi/agent/extensions' \
        '$DOTFILES/base/pi/.pi/agent/agents' \
        '$DOTFILES/base/pi/.pi/agent/APPEND_SYSTEM.md' \
        '$DOTFILES/base/pi/.pi/agent/AGENTS.md' \
        '$DOTFILES/base/pi/.pi/agent/settings.json'"

# Public documentation must remain deployment-blind. Host-specific details
# belong in the deployment repository, not this general-purpose public repo.
# Public-surface guard, widened 2026-10-14: this repo is public and must stay
# decoupled from any particular deployment, so the check covers the rest of the
# public surface too — base/fish (agent-facing helper functions) and the smoke
# harness — not just the pi shared core and docs.
check "public surface: no homelab/agentbox/Telegram deployment references" \
    bash -c "! grep -rEi 'homelab|agentbox|telegram|tg-session|tg-status|pi-telegram|ninimon' \
        '$DOTFILES/README.md' '$DOTFILES/AGENTS.md' '$DOTFILES/TODO.md' \
        '$DOTFILES/docs' '$DOTFILES/base/pi' '$DOTFILES/base/fish' \
        '$DOTFILES/pi-smoke.sh' >/dev/null 2>&1"

# Regression guard for the "use <model>" false-positive bug.  Plain-text
# input switching was removed entirely in 3ebbb2e (Telegram bridge now strips
# the [telegram] prefix and pi handles /use as a slash command).  The only
# guard we still need: the old (?:^|\s) mid-sentence form must never reappear.
check_not "pi: model-switch has no mid-sentence (?:^|\s) anchor (false-positive source)" \
    '\(\?:\^\|\\s\)' "$DOTFILES/base/pi/.pi/agent/extensions/model-switch.ts"

# Regression guard for the guard layer itself. The unit tests verify that
# infra-safety + /check mode correctly classify mutations vs. reads when the
# shell arrives through the native tool (mutation-guard is now hypa-only).
if [[ "$_CAN_STRIP_TS" -eq 1 ]]; then
    check "pi: mutation-guard tests pass" \
        bash -c "cd '$DOTFILES/base/pi/.pi/agent/extensions' && node --experimental-strip-types --test lib/mutation-guard.test.ts"
else
    _skip "pi: mutation-guard tests pass" \
        "node build lacks --experimental-strip-types TS support (need v23+ or TS-compiled build)"
fi

# edit-guardian appends a whitespace-/Unicode-escaped diagnostic when a built-in
# edit fails to match (blank-line count, leading indent, unfolded non-ASCII).
# The pure core lives in lib/ so it is testable and never auto-loaded as an
# extension (root-level *.ts would be); assert the tests + the load split hold.
if [[ "$_CAN_STRIP_TS" -eq 1 ]]; then
    check "pi: edit-guardian diagnostic tests pass" \
        bash -c "cd '$DOTFILES/base/pi/.pi/agent/extensions' && node --experimental-strip-types --test lib/edit-diagnostic.test.ts"
else
    _skip "pi: edit-guardian diagnostic tests pass" \
        "node build lacks --experimental-strip-types TS support (need v23+ or TS-compiled build)"
fi

# pi registers the `powershell` builtin on every platform but it refuses to run
# off Windows, and its presence in the active set makes the system-prompt builder
# emit a "Use PowerShell for file operations..." guideline. The no-powershell
# extension prunes it per-turn on non-win32 hosts (modes' tool gate re-adds it).
check_has "pi: no-powershell extension gates on process.platform (win32 exempt)" \
    'process\.platform' "$DOTFILES/base/pi/.pi/agent/extensions/no-powershell.ts"

if [[ "$_CAN_STRIP_TS" -eq 1 ]]; then
    check "pi: no-powershell platform-tools tests pass" \
        bash -c "cd '$DOTFILES/base/pi/.pi/agent/extensions' && node --experimental-strip-types --test lib/platform-tools.test.ts"
else
    _skip "pi: no-powershell platform-tools tests pass" \
        "node build lacks --experimental-strip-types TS support (need v23+ or TS-compiled build)"
fi

check "pi: edit-guardian test lives in lib/ (never auto-loaded as an extension)" \
    bash -c "! ls '$DOTFILES/base/pi/.pi/agent/extensions'/*.test.ts >/dev/null 2>&1"

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

# Fallback trigger statuses must stay within the capacity/limit allowlist —
# a stray 400/401/500 would misroute normal errors onto the metered twin.
allowed_statuses = {402, 403, 429, 503, 529}
fps = s.get('rateLimitFallbackStatuses')
if fps is not None:
    if not isinstance(fps, list) or not fps:
        sys.stderr.write('rateLimitFallbackStatuses must be a non-empty list\\n')
        sys.exit(1)
    for n in fps:
        if not (isinstance(n, int) and n in allowed_statuses):
            sys.stderr.write('settings.json:rateLimitFallbackStatuses illegal entry: %r\\n' % (n,))
            sys.exit(1)

cd = s.get('rateLimitFallbackRecoveryCooldownSec')
if cd is not None and not (isinstance(cd, int) and cd > 0):
    sys.stderr.write('settings.json:rateLimitFallbackRecoveryCooldownSec must be a positive int\\n')
    sys.exit(1)
\""


# =============================================================================
# 12. NEOVIM SMOKE TEST
# pi-claude-auth → pi-claude-bridge migration. pi-claude-auth copied Claude
# Code's Keychain credential into pi's anthropic auth.json slot and re-synced it
# every 5 minutes, so pi and the claude CLI rotated the same refresh token.
# Route B: the bridge serves the premium roster, inheriting Claude Code's own
# auth. pi's native `/login` route is third-party-repriced and keeps no
# credential (docs/GOTCHAS.md), so nothing here may pin `anthropic/*`.
check_not "pi settings: pi-claude-auth package removed (migrated to claude-bridge)" \
    'pi-claude-auth' "$DOTFILES/base/pi/.pi/agent/settings.json"

check_has "pi settings: claude-bridge declared as a package" \
    'npm:pi-claude-bridge' "$DOTFILES/base/pi/.pi/agent/settings.json"

check_has "pi settings: premium roster routes through claude-bridge" \
    'claude-bridge/claude-opus-5-5' "$DOTFILES/base/pi/.pi/agent/settings.json"

# pi-claude-bridge records `startupNoticeShown` in claude-bridge.json the first
# time it shows its settings notice — writing through the stowed symlink and
# dirtying this repo. Declaring plan + askClaude.enabled up front means the
# notice never fires. Guard both keys, not either.
check "pi: claude-bridge.json suppresses the first-run notice write-back" \
    bash -c "grep -qE '\"plan\"' '$DOTFILES/base/pi/.pi/agent/claude-bridge.json' && \
             grep -qE '\"enabled\"' '$DOTFILES/base/pi/.pi/agent/claude-bridge.json'"

# The /check tool gate is a denylist, so anything that can write indirectly
# stays active unless named: AskClaude can be handed full mode, and subagent
# can spawn the write-capable worker.
check_has "pi: /check mode hides indirect write paths (AskClaude, subagent)" \
    '"edit", "write", "AskClaude", "subagent"' "$DOTFILES/base/pi/.pi/agent/extensions/modes/index.ts"

# kimi left the roster (2 cycle entries) and /chat's model pin. One of the two
# entries (`opencode-go/kimi-k2.6`) no longer existed, so every pi start warned
# "No models match pattern". Tombstone both so they cannot creep back.
check_not "pi settings: kimi removed from the cycle set" \
    'kimi' "$DOTFILES/base/pi/.pi/agent/settings.json"

# /chat must ride the bridge. pi's native OAuth direct route is third-party
# repriced whenever the request carries pi's harness system prompt, which every
# normal session does — a direct pin 400s on every chat turn.
check_has "pi modes: /chat pins the bridge model" \
    'provider: "claude-bridge", id: "claude-sonnet-5-5"' "$DOTFILES/base/pi/.pi/agent/extensions/modes/index.ts"

# ...and the negative: a second, direct pin added alongside the bridge one would
# otherwise slip through the check above.
check_not "pi modes: no direct anthropic model pin" \
    'provider: "anthropic"' "$DOTFILES/base/pi/.pi/agent/extensions/modes/index.ts"

check_not "pi modes: /chat no longer pins a kimi model" \
    'kimi' "$DOTFILES/base/pi/.pi/agent/extensions/modes/index.ts"

# The OpenRouter kimi twin existed to mirror the roster's kimi entry; with the
# primary gone it was an orphan hanging off nothing.
check_not "pi models: orphaned kimi OpenRouter twin removed" \
    'kimi' "$DOTFILES/base/pi/.pi/agent/models.json"

# The roster table calls one model the daily driver, the README says web
# summarisation follows it, and the worker subagent is that same role. All three
# pins must name ONE id — the deepseek-v4-flash / v4.1-flash split survived
# unnoticed for exactly as long as nothing compared them.
check "pi: daily driver is one id (settings, worker agent, web-search summary)" \
    bash -c "python3 -c \"
import json, sys
d = json.load(open('$DOTFILES/base/pi/.pi/agent/settings.json'))['defaultModel']
w = json.load(open('$DOTFILES/base/pi/.pi/web-search.json'))['summaryModel']
m = None
for line in open('$DOTFILES/base/pi/.pi/agent/agents/worker.md'):
    if line.startswith('model: '):
        m = line[len('model: '):].strip()
        break
if len({d, w, m}) != 1:
    sys.stderr.write('daily driver forked: settings=%r worker=%r summary=%r\\n' % (d, m, w))
    sys.exit(1)
\""

# Every agent pins a model, and the roster table documents each role. A pin
# swapped in an agent file but not reflected in the README — or a row left
# pointing at a model nobody pins — is the drift class the deepseek-v4/v4.1
# split thrived in.
check "pi: every agent model pin is documented in the README roster" \
    bash -c "python3 -c \"
import glob, sys
readme = open('$DOTFILES/base/pi/README.md').read()
missing = []
for f in sorted(glob.glob('$DOTFILES/base/pi/.pi/agent/agents/*.md')):
    for line in open(f):
        if line.startswith('model: '):
            m = line[len('model: '):].strip()
            if m not in readme:
                missing.append(f.split('/')[-1] + ' -> ' + m)
            break
if missing:
    sys.stderr.write('undocumented agent pins: %s\\n' % ', '.join(missing))
    sys.exit(1)
\""

# Agents must request the hypa tools, not the builtins they replace: pi-hypa's
# replace filter drops a builtin only when its hypa twin is in the SAME tool
# list, so an agent asking for `bash` gets native bash — which the infra
# write-gate and the /check classifier never see (both hook hypa_shell).
_native_agent_tools=$(grep -REn '^tools:.*(^|[^_a-z])(bash|read|grep|find|ls)([^_a-z]|$)' \
    "$DOTFILES"/base/pi/.pi/agent/agents/ 2>/dev/null || true)
check "pi: agents request the hypa tools, not the replaced builtins" \
    test -z "$_native_agent_tools"

# pi does not validate --tools: it filters the list against what is registered,
# so a typo (`hypa_grp`) silently leaves that agent without the tool.
_bad_agent_tools=$(grep -hE '^tools:' "$DOTFILES"/base/pi/.pi/agent/agents/*.md \
    | tr ',' '\n' | sed -E 's/^tools:[[:space:]]*//' | tr -d ' ' \
    | grep -v '^$' | grep -vE '^(hypa_read|hypa_grep|hypa_find|hypa_ls|hypa_shell|edit|write)$' \
    | sort -u || true)
check "pi: agent tools: lists use only known tool names" \
    test -z "$_bad_agent_tools"

# APPEND_SYSTEM.md rides on every request. It survived two "lean pass" commits
# and regrew to 817 words through incident-driven additions: omission without a
# budget is a phase, not a policy. Any future bump must name the incident behind
# it (see .pi/plans/prompt-slimming.md — host-local, never committed).
_append_words=$(wc -w < "$DOTFILES/base/pi/.pi/agent/APPEND_SYSTEM.md" | tr -d ' ')
check "pi: APPEND_SYSTEM.md within its word budget ($_append_words/500)" \
    test "$_append_words" -le 500
# The other two always-on layers had NO budget, and that is where the growth went: the
# 2026-10-09 slim took APPEND to 498 while the repo AGENTS grew 763 -> 1,168, leaving
# the always-on total 63 words HIGHER than before the exercise. Per-layer budgets, not
# one total: each layer has a different owner and growth rate, and a total cap would
# make project knowledge outbid global rules.
# Global AGENTS' recorded target is 138 words (TODO "prompt-slim watch"); this freezes
# it at 185 until that trim happens, so the 43-word gap stays visible instead of being
# blessed. A bump must name the incident behind it, same rule as APPEND.
_global_agents_words=$(wc -w < "$DOTFILES/base/pi/.pi/agent/AGENTS.md" | tr -d ' ')
check "pi: global AGENTS.md within its word budget ($_global_agents_words/185)" \
    test "$_global_agents_words" -le 185
_repo_agents_words=$(wc -w < "$DOTFILES/AGENTS.md" | tr -d ' ')
check "repo AGENTS.md within its word budget ($_repo_agents_words/1200)" \
    test "$_repo_agents_words" -le 1200
# =============================================================================
section "Neovim smoke test"

if command -v nvim >/dev/null 2>&1; then
    # Parse-only check: verify all Lua config files have valid syntax.
    # This catches typos, wrong module names, and API breakage without
    # needing to bootstrap the full lazy.nvim plugin ecosystem.
    # A full startup test with plugins lives in the CI workflow.
    # -u NONE skips the user init.lua (may be broken on a fresh host and
    # otherwise blocks headless startup on a "Press ENTER" prompt);
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
# 13. TOKENTELEMETRY
# =============================================================================
if [[ -d "$DOTFILES/base/tokentelemetry" ]]; then
    section "TokenTelemetry  [GREEN]"

    _TT_COMPOSE="$DOTFILES/base/tokentelemetry/.config/tokentelemetry/compose.pi.yml"
    _TT_ENV="$DOTFILES/base/tokentelemetry/.config/tokentelemetry/env.tt"

    check "tt: compose file exists" test -f "$_TT_COMPOSE"
    check "tt: env file exists" test -f "$_TT_ENV"
    check "tt: README.md exists" test -f "$DOTFILES/base/tokentelemetry/README.md"
    check "tt: UPSTREAM.md exists" test -f "$DOTFILES/base/tokentelemetry/UPSTREAM.md"

    # Image digests must be pinned with @sha256: in env.tt
    check_has "tt: backend image pinned with @sha256:" \
        'TT_BACKEND_IMAGE=.*@sha256:[0-9a-f]{64}' "$_TT_ENV"
    check_has "tt: frontend image pinned with @sha256:" \
        'TT_FRONTEND_IMAGE=.*@sha256:[0-9a-f]{64}' "$_TT_ENV"

    # Loopback-only port binding
    check_has "tt: backend binds to 127.0.0.1 only" \
        '127\.0\.0\.1:\$\{TT_BACKEND_PORT' "$_TT_COMPOSE"
    check_has "tt: frontend binds to 127.0.0.1 only" \
        '127\.0\.0\.1:\$\{TT_FRONTEND_PORT' "$_TT_COMPOSE"

    # Pi + Claude Code sessions mount
    check_has "tt: ~/.pi mounted read-only" \
        'HOME}/.pi:/root/.pi:ro' "$_TT_COMPOSE"
    check_has "tt: ~/.claude mounted read-only" \
        'HOME}/.claude:/root/.claude:ro' "$_TT_COMPOSE"

    # Data bind-mount (not named volume)
    check_has "tt: data dir bind-mounted on host" \
        'local/share/tokentelemetry' "$_TT_COMPOSE"

    # No build: blocks — must use pre-built images
    check_not "tt: no build blocks (uses pre-built images)" \
        '^\s+build:' "$_TT_COMPOSE"

    # Compose file must parse cleanly (skip if docker / compose plugin
    # not callable — Docker Desktop's WSL shim makes `command -v docker`
    # succeed even when WSL integration is off for this distro).
    # `docker compose config -q` is purely client-side; daemon-up is NOT required.
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        check "tt: compose file parses" \
            docker compose -f "$_TT_COMPOSE" --env-file "$_TT_ENV" config -q
    else
        _skip "tt: compose file parses" "docker / compose plugin not callable in this env"
    fi

    # fish tt function
    _TT_FISH="$DOTFILES/base/fish/.config/fish/functions/tt.fish"
    if [[ -f "$_TT_FISH" ]]; then
        check "tt: tt.fish exists in base/fish" test -f "$_TT_FISH"
        if command -v fish >/dev/null 2>&1; then
            check "tt: tt.fish parses (fish -n)" \
                fish -n "$_TT_FISH"
        fi
    fi
fi



# =============================================================================
# ── pi session retention ─────────────────────────────────────────────────────
# Session transcripts are disposable runtime state, but the age gate is
# load-bearing: an edit that dropped -mtime would turn this into "delete every
# session". pi has no retention setting of its own.
section "Pi session retention"

_PI_PRUNE="$DOTFILES/base/fish/.config/fish/functions/pi-prune-sessions.fish"
check "pi-prune-sessions: function exists in base/fish" test -f "$_PI_PRUNE"
if command -v fish >/dev/null 2>&1; then
    check "pi-prune-sessions: parses (fish -n)" \
        fish -n "$_PI_PRUNE"
fi
check_has "pi-prune-sessions: keeps the -mtime age gate" \
    '[[:space:]]-mtime' "$_PI_PRUNE"
check "pi-prune-sessions: every -delete is guarded (-mtime or -empty)" \
    bash -c "! grep -- '-delete' '$_PI_PRUNE' | grep -qvE -- '-mtime|-empty'"

# ── pi settings drift ────────────────────────────────────────────────────────
# pi persists runtime state (selected model, theme, thinking level,
# lastChangelogVersion, package list) into ~/.pi/agent/settings.json, which this
# repo owns as a stowed symlink into base/pi/.pi/agent/settings.json — so every
# session writes into a TRACKED file. pi 1.3.0 locks those writes and merges them
# per top-level key, so concurrent sessions do not lose each other's *unrelated*
# keys; what remains is file-vs-HEAD drift. Left alone it gets swept into whatever
# commit is next, and it can turn the assertions above red (defaultModel,
# enabledModels, the kimi tombstone all read the live file).
section "Pi settings drift"

_PI_SETTINGS_RESET="$DOTFILES/base/fish/.config/fish/functions/pi-settings-reset.fish"
check "pi-settings-reset: function exists in base/fish" test -f "$_PI_SETTINGS_RESET"
# The fish .gitignore is an allowlist, so a new own-file silently drops out of the
# repo without this (the generic class-wide guard is further down too).
check_has "pi-settings-reset: not gitignored (fish allowlist negation present)" \
    '!functions/pi-settings-reset\.fish' "$DOTFILES/base/fish/.config/fish/.gitignore"
if command -v fish >/dev/null 2>&1; then
    check "pi-settings-reset: parses (fish -n)" \
        fish -n "$_PI_SETTINGS_RESET"
fi
# The two keys whose LIVE value must survive the revert, because each marks a
# deliberate act: the upgrade marker this repo records on purpose, and
# `pi install` / `pi remove` (reverting those would silently undo them). The
# assertion matches the whole keep-set expression, not the bare key name — the
# name appears in the header comment too, so a bare match would pass after the
# key was dropped from KEEP.
check_has "pi-settings-reset: keep set is the marker plus packages" \
    'KEEP = .*"lastChangelogVersion", "packages"' "$_PI_SETTINGS_RESET"
# The whole mechanism rests on the live file BEING the tracked file. When it is
# not stowed, pi writes host-local settings and reconciling would overwrite a file
# nothing reads — so that case must refuse, not proceed.
check_has "pi-settings-reset: refuses when the live file is not stowed" \
    'is not stowed to' "$_PI_SETTINGS_RESET"
# Our write does not take pi's lock, so it has to verify exact bytes (kept keys
# included, or a `pi install` landing mid-run is clobbered) and retry a bounded
# number of times instead of assuming the replace landed.
check_has "pi-settings-reset: writes atomically (os.replace)" \
    'os\.replace\(tmp, tracked\)' "$_PI_SETTINGS_RESET"
check_has "pi-settings-reset: verifies exact bytes after writing" \
    'if read_bytes\(\) == out\.encode\("utf-8"\)' "$_PI_SETTINGS_RESET"
check_has "pi-settings-reset: bounds the retry loop" \
    'for attempt in range\(3\)' "$_PI_SETTINGS_RESET"
# A torn pi write can leave invalid JSON, invalid UTF-8, or a non-object; all
# three are states this exists to repair, and only HEAD has to parse.
check_has "pi-settings-reset: treats a torn write as recoverable, not an error" \
    'except json\.JSONDecodeError' "$_PI_SETTINGS_RESET"
check_has "pi-settings-reset: an unreadable file is archived, not silently replaced" \
    'settings\.json\.unparsable-' "$_PI_SETTINGS_RESET"
check_has "pi-settings-reset: rejects non-object JSON too" \
    'isinstance\(live, dict\)' "$_PI_SETTINGS_RESET"
# A revert that still shows as modified is a revert that gets committed anyway.
check_has "pi-settings-reset: restores HEAD verbatim when the values match" \
    'head_raw if same else' "$_PI_SETTINGS_RESET"

if command -v fish >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    # Functional, against a throwaway git repo and through the helper, so the real
    # agent dir is never touched. Policy under test: repo wins, undeclared keys go,
    # deliberate acts stay — and the rewrite keeps pi's no-trailing-newline format.
    # commit.gpgsign=false: this host signs by default, and a throwaway repo has no
    # signing key, so an inherited config would fail the fixture, not the code.
    check "pi-settings-reset: reverts drift, drops undeclared keys, keeps deliberate acts" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            mkdir -p "$d/base/pi/.pi/agent"; f="$d/base/pi/.pi/agent/settings.json"
            printf "%s" "{\"defaultModel\": \"a\", \"lastChangelogVersion\": \"1.0.0\", \"packages\": [\"npm:x\"]}" > "$f"
            git -C "$d" init -q; git -C "$d" add -A
            git -C "$d" -c commit.gpgsign=false -c user.email=t@t -c user.name=t commit -qm head
            printf "%s" "{\"defaultModel\": \"b\", \"lastChangelogVersion\": \"1.1.0\", \"packages\": [\"npm:x\", \"npm:y\"], \"theme\": \"light\"}" > "$f"
            fish -c "source \"$1\"; __pi_settings_reset_apply \"$d\" base/pi/.pi/agent/settings.json 0 0" >/dev/null 2>&1
            grep -q "\"defaultModel\": \"a\"" "$f" &&
            ! grep -q theme "$f" &&
            grep -q "npm:y" "$f" &&
            grep -q "1\.1\.0" "$f" &&
            test -n "$(tail -c 1 "$f")"' _ "$_PI_SETTINGS_RESET"
    # --all must land byte-for-byte on HEAD (git diff catches a reformat that a
    # value comparison would not), and --dry-run must not write at all.
    check "pi-settings-reset: --all lands byte-identical on HEAD; --dry-run writes nothing" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            mkdir -p "$d/base/pi/.pi/agent"; f="$d/base/pi/.pi/agent/settings.json"
            printf "%s" "{\"defaultModel\": \"a\", \"packages\": [\"npm:x\"]}" > "$f"
            git -C "$d" init -q; git -C "$d" add -A
            git -C "$d" -c commit.gpgsign=false -c user.email=t@t -c user.name=t commit -qm head
            printf "%s" "{\"defaultModel\": \"b\", \"packages\": [\"npm:x\", \"npm:y\"]}" > "$f"
            h=$(shasum "$f")
            fish -c "source \"$1\"; __pi_settings_reset_apply \"$d\" base/pi/.pi/agent/settings.json 0 1" >/dev/null 2>&1
            test "$(shasum "$f")" = "$h" || exit 1
            fish -c "source \"$1\"; __pi_settings_reset_apply \"$d\" base/pi/.pi/agent/settings.json 1 0" >/dev/null 2>&1
            git -C "$d" diff --quiet -- base/pi/.pi/agent/settings.json' _ "$_PI_SETTINGS_RESET"
    # Two states that are drift without a value difference, so a value-only
    # comparison would report "no drift" and leave the repo dirty (reordered keys,
    # stray newline); plus the torn write it is meant to repair, which must hand
    # the unreadable bytes back instead of dropping them.
    check "pi-settings-reset: repairs formatting-only drift and an unparsable file" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            mkdir -p "$d/base/pi/.pi/agent"; f="$d/base/pi/.pi/agent/settings.json"
            rel=base/pi/.pi/agent/settings.json
            printf "%s" "{\"defaultModel\": \"a\", \"packages\": [\"npm:x\"]}" > "$f"
            git -C "$d" init -q; git -C "$d" add -A
            git -C "$d" -c commit.gpgsign=false -c user.email=t@t -c user.name=t commit -qm head
            printf "%s\n" "{\"packages\": [\"npm:x\"], \"defaultModel\": \"a\"}" > "$f"
            fish -c "source \"$1\"; __pi_settings_reset_apply \"$d\" $rel 0 0 \"$d/backups\"" >/dev/null 2>&1
            git -C "$d" diff --quiet -- $rel || exit 1
            printf "%s" "{\"defaultModel\": \"a\", \"packa" > "$f"
            fish -c "source \"$1\"; __pi_settings_reset_apply \"$d\" $rel 0 0 \"$d/backups\"" >/dev/null 2>&1
            test $? -eq 1 || exit 1
            git -C "$d" diff --quiet -- $rel || exit 1
            ls "$d"/backups/settings.json.unparsable-* >/dev/null 2>&1 || exit 1
            grep -q "packa" "$d"/backups/settings.json.unparsable-*' _ "$_PI_SETTINGS_RESET"
    # The public function is where the stow guard, the argument handling and the
    # exit codes live, so it needs exercising too. --no-config plus a sanitised
    # PATH: the real config.fish prepends mise shims, and a shim cannot start
    # against a throwaway HOME (a harness artefact, not a function bug). The repo
    # is committed FIRST so the not-stowed case cannot be satisfied by the earlier
    # "no HEAD commit" bail — it has to fail on the stow guard itself.
    check "pi-settings-reset: public function refuses host-local/bad args, reconciles a stowed file" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            rel=base/pi/.pi/agent/settings.json
            p=/usr/bin:/bin:/usr/sbin:/sbin
            mkdir -p "$d/dotfiles/base/pi/.pi/agent" "$d/.pi/agent"
            printf "%s" "{\"defaultModel\": \"a\", \"packages\": [\"npm:x\"]}" > "$d/dotfiles/$rel"
            git -C "$d/dotfiles" init -q; git -C "$d/dotfiles" add -A
            git -C "$d/dotfiles" -c commit.gpgsign=false -c user.email=t@t -c user.name=t commit -qm head
            # host-local: a regular file, not the stowed symlink
            printf "%s" "{\"defaultModel\": \"a\"}" > "$d/.pi/agent/settings.json"
            msg=$(env HOME="$d" PATH=$p "$1" --no-config -c "source \"$2\"; pi-settings-reset" 2>&1)
            test $? -eq 1 || exit 1
            printf "%s" "$msg" | grep -q "is not stowed to" || exit 1
            grep -q "defaultModel" "$d/.pi/agent/settings.json" || exit 1
            env HOME="$d" PATH=$p "$1" --no-config -c "source \"$2\"; pi-settings-reset --bogus" >/dev/null 2>&1
            test $? -eq 2 || exit 1
            # now stowed: the same file must reconcile
            rm "$d/.pi/agent/settings.json"
            ln -s "$d/dotfiles/$rel" "$d/.pi/agent/settings.json"
            printf "%s" "{\"defaultModel\": \"b\", \"packages\": [\"npm:x\"]}" > "$d/dotfiles/$rel"
            env HOME="$d" PATH=$p "$1" --no-config -c "source \"$2\"; pi-settings-reset" >/dev/null 2>&1 || exit 1
            test -L "$d/.pi/agent/settings.json" || exit 1
            git -C "$d/dotfiles" diff --quiet -- "$rel"' _ "$(command -v fish)" "$_PI_SETTINGS_RESET"
else
    _skip "pi-settings-reset: functional tests" "fish + python3 not both callable in this env"
fi

# ── pi worktree helper ───────────────────────────────────────────────────────
# pwt pairs a git worktree with a tmux window and a pinned pi session id, so two
# agents can work in one repo without sharing a working tree. The pinned id is
# the load-bearing part: resuming by "most recent for cwd" collides as soon as a
# repo holds two sessions.
section "pi worktree helper (pwt)"

_PWT="$DOTFILES/base/fish/.config/fish/functions/pwt.fish"
check "pwt: function exists in base/fish" test -f "$_PWT"
if command -v fish >/dev/null 2>&1; then
    check "pwt: parses (fish -n)" \
        fish -n "$_PWT"
fi
check_has "pwt: pins an explicit pi session id" \
    '\-\-session-id' "$_PWT"
# worktree remove deletes IGNORED files without complaint, so pwt must refuse.
check_has "pwt: refuses removal while ignored files are present" \
    'porcelain --ignored' "$_PWT"
# Two pi processes on one --session-id resume the SAME transcript JSONL and pi
# rewrites that file from its own memory, so the second writer silently clobbers
# the first. An open window must therefore be reused, never duplicated.
check_has "pwt: reuses an open window instead of spawning a second pi" \
    'tmux select-window -t' "$_PWT"
check_has "pwt: finds that window by pane cwd" \
    'list-panes -a' "$_PWT"
# A workstream window belongs to the session that owns the repo's MAIN checkout, not
# to whichever session the user happened to be sitting in — otherwise a project's
# worktrees pile up in a scratch session. The signal is `session_path`: RECORDED at
# creation by whoever made the session (sesh runs `new-session -c <path>`), never the
# pane's live cwd. Panes cd, and a scratch session routinely hosts worktree panes (this
# machine's session `0` does), so a cwd or in-tree match would resolve THAT session as
# the parent of the very repo whose worktree it holds — the bug this feature fixes.
check_has "pwt: opens the window in the session that owns the repo" \
    '__pwt_parent_session' "$_PWT"
check_has "pwt: resolves that session from the recorded session_path" \
    'session_path' "$_PWT"
check_has "pwt: reads sessions for it, not pane paths" \
    'list-sessions -F' "$_PWT"
# ONE canonicaliser, not two: the resolver must ask for the same canonical form as the
# window lookups, or the same checkout can compare unequal to itself and pwt opens a
# second pi on one transcript. (Why it is not a `cd` is asserted on __pwt_realpath
# itself, above.) Bodies are delimited by the next `function`, since a fish function's
# body also ends in `end`.
check "pwt: the parent-session resolver reuses the shared canonicaliser" \
    bash -c 'awk "/^function __pwt_parent_session /{f=1} f && /^function / && !/^function __pwt_parent_session /{exit} f" "$1" | grep -v "^[[:space:]]*#" | grep -q __pwt_realpath' \
    _ "$_PWT"
# Ordering, not presence: the client has to be in the target session BEFORE the
# source can be destroyed by the move (detach-on-destroy is on by default), and a
# headless test cannot observe a detach.
check "pwt: the client moves before the window leaves its session" \
    bash -c 'body=$(awk "/^function __pwt_snap_home /{f=1} f && /^function / && !/^function __pwt_snap_home /{exit} f" "$1" | grep -v "^[[:space:]]*#")
             n=$(printf "%s\\n" "$body" | grep -n switch-client | head -1 | cut -d: -f1)
             m=$(printf "%s\\n" "$body" | grep -n move-window | head -1 | cut -d: -f1)
             [[ -n "$n" && -n "$m" && "$n" -lt "$m" ]]' \
    _ "$_PWT"
# A session ID, not a name: tmux rewrites '.'/':' in a session NAME, and a name
# starting with '$' cannot be targeted by name at all.
check_has "pwt: targets the window by session id" \
    '\-t "\$sess:"' "$_PWT"
check_has "pwt: asks tmux for session ids" \
    '#\{session_id\}' "$_PWT"
# `=` is load-bearing on the name tier: a bare session target is a PREFIX match, so a
# repo `foo` would be answered by `foobar`'s session the moment its own is gone.
check_has "pwt: the name tier matches exactly, never as a prefix" \
    'has-session -t "=\$want"' "$_PWT"
# ...and tmux's '.'-to-'_' rewrite means a dotted repo has to be looked up under the
# rewritten name, or that whole tier is dead for it.
check_has "pwt: the name tier allows for tmux rewriting '.'" \
    "replace -a -r '\[.:\]' '_'" "$_PWT"
# select-window cannot cross sessions: without the jump the window opens in the parent
# session and the command looks like it did nothing at all.
check_has "pwt: follows the window into the parent session" \
    '__pwt_jump_to "\$pane"' "$_PWT"
check_not "pwt: never places the new window with a bare select-window" \
    'select-window -t "\$pane"' "$_PWT"
# The session can vanish between that listing and the spawn. Falling back to the
# caller's session beats leaving a freshly created worktree with no window at all —
# but not before ruling out a window for this sid that exists with its id lost, since
# respawning there would put TWO pis on one --session-id and clobber one transcript.
# That guard is asserted textually only: forcing `new-window` to create a window and
# then lose its id needs a tmux shim, and a shim is more likely to be wrong than the
# race is to happen (same reasoning as the died-on-reload branch below).
check_has "pwt: falls back to the caller's session when the target is gone" \
    'test -z "\$pane"' "$_PWT"
check_has "pwt: refuses a second pi when the window exists but its id was lost" \
    'already exists — jumped to it' "$_PWT"
# Placement is MAINTAINED, not one-shot: a window that landed in the caller's session
# because its project session did not exist yet moves home the next time you go to it
# (reuse through `pwt <slug>`, or `pwt jump`). Those two verbs rather than a snap verb of
# its own, because the panel's `enter` already reaches both.
check_has "pwt: re-homes a reused window into its repo's session" \
    'move-window -s' "$_PWT"
# Only windows pwt opened are relocated (the gate covers BOTH callers, including the
# path fallback that can match a pi started by hand inside the worktree), and a MOVE
# needs the recorded path rather than a matching session name.
check_has "pwt: relocates only windows that carry a pwt session id" \
    'display-message -p -t "\$wid" .#\{@pwt_sid\}' "$_PWT"
check_has "pwt: a move requires the recorded path, not a matching name" \
    'path-only' "$_PWT"
# The whole design says sessions are sesh's to create. A snap that created one to
# move into would be a second session manager, and it must stay impossible. Comments
# are stripped: the resolver's own comment names `new-session -c <path>` to explain
# where session_path comes from, and a plain grep would match that instead of a call.
check "pwt: never creates a session to snap into" \
    bash -c '! grep -v "^[[:space:]]*#" "$1" | grep -q new-session' _ "$_PWT"
# tmux reports the RESOLVED path (a window at /tmp shows /private/tmp) while git
# and find hand back the path as given, so a checkout behind any symlinked parent
# would never match and pwt would spawn the duplicate after all.
check_has "pwt: compares window paths canonically" \
    'path resolve' "$_PWT"
# ...with a BUILTIN, never a `cd …; pwd -P` round trip. A fish function runs in the
# caller's process, so cd'ing there fires a PWD-change event on every comparison (direnv
# hooks PWD), and the shell had to be put back afterwards — bookkeeping whose failure
# mode was a shell left inside a directory pwt had just deleted. Asserted on the
# FUNCTION BODY: a bare grep would match the comment explaining why it is not done.
check "pwt: canonicalises without cd'ing the caller's shell" \
    bash -c 'body=$(awk "/^function __pwt_realpath /{f=1} f && /^function / && !/^function __pwt_realpath /{exit} f" "$1" | grep -v "^[[:space:]]*#")
             printf "%s\n" "$body" | grep -q "path resolve" \
               && ! printf "%s\n" "$body" | grep -qE "(^|[[:space:]])cd([[:space:]]|\$)|pwd -P"' \
    _ "$_PWT"
# A live window means the worktree is in use: removing it pulls the directory out
# from under a running pi, so the ignored-file guard is not the only one. This one
# is deliberately NOT gated on $TMUX — `pwt rm` from a plain terminal while pi
# works in tmux is exactly when it matters.
check_has "pwt: refuses removal while a window still holds the worktree" \
    'window \$live still holds' "$_PWT"
# Reuse must require an actual pi: a plain shell cd'd into the worktree is not a
# workstream, but it IS enough to make removal unsafe. Removal additionally has to
# see a pane that cd'd into a SUBDIRECTORY — deleting the tree under it leaves that
# shell in a directory that no longer exists.
check_has "pwt: distinguishes a pi window from a shell in the worktree" \
    'case pi-only' "$_PWT"
check_has "pwt: treats a pane anywhere inside the worktree as in use" \
    'case in-tree' "$_PWT"
# The state tap: pwt attaches it as it opens a pane, and adopts one when the panel
# jumps to a live session. The attach string goes through strftime BEFORE tmux
# expands formats — a literal pane id (%3) is mangled to "3" and every later
# `tmux -t 3` silently targets WINDOW index 3 — so #{pane_id} is the only safe
# channel. And never `-o`: tmux closes an existing pipe before evaluating -o, so a
# second attach would DETACH the tap instead of no-oping.
check_has "pwt: attaches the pi state tap when it opens a window" \
    'pipe-pane' "$_PWT"
check_has "pwt: names the tap's pane with #{pane_id}, never a literal id" \
    'pwt-osc #\{pane_id\}' "$_PWT"
check_not "pwt: never attaches the tap with pipe-pane -o" \
    'pipe-pane -o' "$_PWT"
check_has "pwt: adopts a live session when the C-w panel jumps to it" \
    '__pwt_tap' "$_PWT"
# The in-place rung: a workstream with no worktree, for repos a fresh checkout
# cannot serve (a git-crypt repo fails `worktree add` at the smudge filter) or
# where the per-worktree state is not worth re-provisioning.
check_has "pwt: exposes an in-place workstream verb" \
    'case here' "$_PWT"
check_has "pwt: rejects a base ref for the in-place verb" \
    'takes no base ref' "$_PWT"
# Identity, not cwd: two in-place workstreams share one directory, so matching on
# the path would hand the second one the first one's window and its transcript.
check_has "pwt: records the workstream identity on the window it opens" \
    '@pwt_sid' "$_PWT"
check_has "pwt: reuses by that identity before falling back to the path" \
    '__pwt_workstream_window' "$_PWT"
# ...but that fallback is for worktrees only: an in-place workstream shares its
# directory, so a window found there may belong to a different one. Without this the
# second label silently lands in the first label's window and never exists.
check_has "pwt: reuses an in-place workstream by identity alone" \
    'identity-only' "$_PWT"
# Neither the sid nor the repo root can be unique on their own: the sid is derived
# from the repo's BASENAME (two repos can share it, and `here` shares it with a
# worktree of the same name) while a here window and a worktree window in one repo
# share the root. The window records the workstream's own directory instead, and is
# matched on sid AND dir; the fallback tier is restricted to windows with NO dir so
# the fix cannot reintroduce the hijack for pairs it just separated.
check_has "pwt: records the workstream's own directory on the window" \
    '@pwt_dir' "$_PWT"
check_has "pwt: the pre-marker fallback needs an unmarked window" \
    'test -z "\$parts\[4\]"' "$_PWT"
# __worktrees/ must be invisible to everything that is not pwt: an untracked dir has
# `git add -A` stage a mode-160000 gitlink for the worktree, and it doubles every
# ripgrep/editor hit. info/exclude is per-clone and uncommitted, so no target repo
# has to commit an ignore rule.
check_has "pwt: hides __worktrees from the parent repo" \
    'info/exclude' "$_PWT"
# A missing pi makes the pane exit at once and tmux takes the window with it, so the
# worktree would be created and nothing would be shown.
check_has "pwt: preflights pi before spawning a window" \
    'command -sq pi' "$_PWT"
check_has "pwt: reports a window that died at birth" \
    'died at birth' "$_PWT"
# No legitimate commit-ish starts with '-' — git would parse it as an OPTION.
check_has "pwt: rejects a base ref git would parse as an option" \
    'invalid base ref' "$_PWT"
# Two in-place workstreams share one working tree: warn, never refuse (the rung
# exists for repos a worktree cannot serve).
check_has "pwt: warns when a second in-place workstream shares a working tree" \
    'parallel edits will collide' "$_PWT"
# `worktree remove` succeeds first, so `branch -d` refusing an unmerged branch must
# name the follow-up rather than leave a bare git hint.
check_has "pwt: names the branch left behind by an unmerged rm" \
    'not fully merged' "$_PWT"
# `--stash` is the panel's confirmed teardown: close the window, keep the work, remove
# the tree. The parking path is what makes it safe — ignored files are MOVED, never
# deleted, under the git common dir.
check_has "pwt: exposes a preserve-and-remove mode" \
    '\-\-stash' "$_PWT"
check_has "pwt: parks ignored files instead of deleting them" \
    'pwt-removed' "$_PWT"
check_has "pwt: exposes a close verb for live workstreams" \
    'case close' "$_PWT"
# A workstream's pi runs with no shell around it, so its environment is fixed at
# exec: pwt hands the secrets to the SPAWN (tmux -e) instead of pushing them into the
# server, where a value would outlive the command and be inherited by every later
# window, including ones pwt never opened.
check_has "pwt: hands the secrets env to the window it spawns" \
    '\$envargs pi --session-id' "$_PWT"
# ...read from the FILE at call time, not from the calling shell's exports: pwt is
# normally typed into a pane older than the edit, and reload exists to pick an edit
# up — forwarding the caller's copy would re-inject the stale secret and report
# success.
check_has "pwt: reads the secrets file instead of the caller's exports" \
    'source "\$file"' "$_PWT"
# The live secrets file carries commented-out `set -gx NAME` lines (retired keys), so
# an unanchored scrape forwards names that were deliberately retired.
check_has "pwt: anchors the secrets scrape" \
    '\[\[:space:\]\]\*set' "$_PWT"
# tmux owns TERM; the server's PATH carries the mise shims via tmux.conf.
check_has "pwt: never forwards TERM/PATH/TMUX" \
    'TERM TMUX TMUX_PANE PWD OLDPWD HOME PATH' "$_PWT"
# `-e NAME=` would CLEAR a secret the window would otherwise inherit.
check_has "pwt: skips an empty secret instead of clearing it" \
    'set -q \$name' "$_PWT"
# remain-on-exit is off in the shipped tmux.conf, but a corpse keeps answering with a
# pane id, so the survival check has to look at pane_dead too.
check_has "pwt: a reload that died is not reported as a reload" \
    'pane_dead' "$_PWT"
check_has "pwt: exposes a reload verb for a live workstream" \
    'case reload' "$_PWT"
# A live process cannot be given new env, so reload IS a restart — and respawn-pane
# is the only restart that keeps the pane id, the window name and the @pwt_* marks.
check_has "pwt: reload respawns the pane in place" \
    'respawn-pane -k' "$_PWT"
check_has "pwt: reload refuses a window with no recorded session id" \
    'records no pwt session id' "$_PWT"
check_has "pwt: reload refuses to kill a working agent" \
    'a reload would drop the current turn' "$_PWT"
check_has "pwt: reload clears the dead run's state flags" \
    '-u @pi_state' "$_PWT"
check_has "pwt: reload re-attaches the state tap" \
    '__pwt_tap "\$pane"' "$_PWT"
check_has "pwt: reload finds a pi that cd'd inside the workstream" \
    'pi-only in-tree no-worktrees pane-id' "$_PWT"
# `test -n (tmux display-message …)` collapses to a lone `-n` when the command prints
# nothing, and `-n` is a non-empty STRING — a survival check that can never fail. The
# result has to be stored in a variable first. Asserted as a CLASS, because the pattern
# had already crept into the `rm --stash` window check, where it turned "the window is
# already gone" into a refusal. Scoped to tmux on purpose: `display-message` really can
# print nothing, while the `tail -c 1` next to it cannot on a non-empty file (verified
# — fish yields ZERO elements for empty output and ONE empty element for a stripped
# newline, and only the former collapses).
check_not "pwt: never tests a tmux query with test -n (vacuous on empty)" \
    'test -n \(command tmux' "$_PWT"
check_has "pwt: stores the reload survival check before testing it" \
    'set -l alive' "$_PWT"
check_has "pwt: the doc says what --stash preserves" \
    'pwt-removed' "$DOTFILES/docs/PWT.md"

# The written contract. pwt's design lives in code comments and this suite; a real
# tool ships the parts a user has to know.
check "pwt: has a user-facing contract doc" test -f "$DOTFILES/docs/PWT.md"
check_has "pwt: the doc states the __worktrees ignore rule" \
    'info/exclude' "$DOTFILES/docs/PWT.md"
check_has "pwt: the doc states the in-place shared-tree caveat" \
    'shares? one working tree' "$DOTFILES/docs/PWT.md"
check_has "pwt: the doc states the notification mute switch" \
    '@pwt_notify' "$DOTFILES/docs/PWT.md"
check_has "pwt: help points at the doc" \
    'docs/PWT' "$_PWT"
check_has "pwt: the doc states the reload recipe" \
    'pwt reload --force' "$DOTFILES/docs/PWT.md"
check_has "pwt: the doc states the tmux floor for -e" \
    'tmux 3.2 or newer' "$DOTFILES/docs/PWT.md"
check_has "pwt: the doc says the env is deliberately not pushed to the server" \
    'setenv -g' "$DOTFILES/docs/PWT.md"
# Where the window lands is a stated contract, not an implementation detail: the
# resolver's signal and the fact that pwt creates no session are what a future editor
# is most likely to "simplify" back into the cwd-matching bug.
check_has "pwt: the doc states where the window opens" \
    'Where the window opens' "$DOTFILES/docs/PWT.md"
check_has "pwt: the doc names the recorded session_path signal" \
    'session_path' "$DOTFILES/docs/PWT.md"
check_has "pwt: the doc warns the project session takes its workstreams with it" \
    'dies with that' "$DOTFILES/docs/PWT.md"
check_has "AGENTS.md: points at docs/PWT.md" \
    'docs/PWT\.md' "$DOTFILES/AGENTS.md"

if command -v fish >/dev/null 2>&1; then
    # Behavioural, no tmux needed: the ignore rule is written on create, and a
    # second run must not append a duplicate line.
    check "pwt: hides __worktrees from git status, add -A, and indexers" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT; cd "$d"; git init -q repo; cd repo
            git config user.email t@t; git config user.name t; echo x > f; git add f
            git -c commit.gpgsign=false commit -qm init
            printf %s node_modules/ > .git/info/exclude
            env -u TMUX "$1" -c "source $2; pwt demo" >/dev/null 2>&1
            [[ -d __worktrees/demo ]] || exit 1
            git check-ignore -q __worktrees/demo || exit 1
            [[ -z "$(git status --porcelain)" ]] || exit 1
            git add -A || exit 1
            ! git ls-files -s | grep -q "^160000" || exit 1
            [[ "$(grep -cxF -- "__worktrees/" .git/info/exclude)" == "1" ]] || exit 1
            [[ "$(head -1 .git/info/exclude)" == "node_modules/" ]] || exit 1
            [[ "$(grep -c "^$" .git/info/exclude)" == "0" ]] || exit 1
            env -u TMUX "$1" -c "source $2; pwt demo" >/dev/null 2>&1
            [[ "$(grep -cxF -- "__worktrees/" .git/info/exclude)" == "1" ]]' \
        _ "$(command -v fish)" "$_PWT"
    # TMUX is set so the preflight path runs, but no server is touched: the guard must
    # fire before anything is created. PATH is the real one minus pi's own directory,
    # so the test is not vacuous on a machine that keeps pi elsewhere. --no-config is
    # load-bearing: fish sources config.fish even for -c, and this repo's config re-adds
    # ~/.local/bin (where pi lives) to PATH, which would defeat the restricted PATH.
    _pi_dir="$(dirname "$(command -v pi 2>/dev/null || printf /nonexistent/pi)")"
    _no_pi_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF -- "$_pi_dir" | paste -sd: -)"
    check "pwt: refuses to spawn a window when pi is not on PATH" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT; cd "$d"; git init -q repo; cd repo
            git config user.email t@t; git config user.name t; echo x > f; git add f
            git -c commit.gpgsign=false commit -qm init
            out=$(env TMUX=/nonexistent PATH="$1" "$2" -N -c "source $3; pwt demo" 2>&1)
            rc=$?
            [[ $rc -ne 0 && ! -d __worktrees/demo && "$out" == *"pi is not on PATH"* ]]' \
        _ "$_no_pi_path" "$(command -v fish)" "$_PWT"
    # The name list comes from the FILE and its values win over the caller's exports
    # (a stale pane must not re-inject a rotated secret); the vars tmux owns are never
    # forwarded (the fixture names them, so that assertion is not vacuous), and a name
    # with an empty value is skipped rather than sent as `-e NAME=`, which would CLEAR
    # it. Nothing here asserts the died-on-reload branch: it races the respawn (tmux
    # returns before the child has exec'd), so the code checks pane_dead and this suite
    # only asserts that check exists.
    check "pwt: forwards the file's secrets, not the caller's stale exports" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            printf "%s\n" "set -gx REAL fromfile" "set -gx TERM fromfile-term" \
                "set -gx PATH fromfile-path" "# set -gx RETIRED nope" > "$d/secrets.fish"
            out=$(env PWT_SECRETS="$d/secrets.fish" REAL=fromshell RETIRED=stale TERM=xterm \
                "$1" -N -c "source $2; __pwt_forward_env" 2>&1)
            [[ "$out" == *"REAL=fromfile"* ]] || exit 1
            [[ "$out" != *"RETIRED"* ]] || exit 1
            [[ "$out" != *"TERM="* && "$out" != *"PATH="* ]] || exit 1
            [[ "$(printf "%s\n" "$out" | grep -c "^-e$")" == "1" ]]' \
        _ "$(command -v fish)" "$_PWT"
    check "pwt: PWT_FORWARD_ENV overrides the list, skipping unset names" \
        bash -c 'out=$(env PWT_FORWARD_ENV="PRESENT ABSENT TERM" PRESENT=yes TERM=xterm \
                "$1" -N -c "source $2; __pwt_forward_env" 2>&1)
            [[ "$out" == *"PRESENT=yes"* ]] || exit 1
            [[ "$out" != *"ABSENT"* && "$out" != *"TERM="* ]] || exit 1
            blank=$(env PWT_FORWARD_ENV= "$1" -N -c "source $2; __pwt_forward_env" 2>&1)
            [[ -z "$blank" ]]' \
        _ "$(command -v fish)" "$_PWT"
    # Where a workstream window LANDS, behaviourally. The sessions stand in for the
    # real thing: `project` was created AT the repo root — what sesh's
    # `new-session -c <path>` sets in session_path — `scratch` elsewhere, and `wt`
    # INSIDE the worktree pwt makes, which is the session a cwd-based resolver would
    # hand the window to. `-f /dev/null` keeps the user's tmux.conf out of the test, so
    # no plugin renames the window and no hook fires; the stub `pi` holds the pane open
    # so the @pwt_* mark can land (a window that dies cannot take window options).
    if command -v tmux >/dev/null 2>&1; then
        _ps_dir="$(mktemp -d)"
        _ps_sock="$_ps_dir/sock"
        mkdir -p "$_ps_dir/stub" "$_ps_dir/elsewhere"
        printf '#!/bin/sh\nexec sleep 300\n' > "$_ps_dir/stub/pi"
        chmod +x "$_ps_dir/stub/pi"
        git init -q "$_ps_dir/repo"
        git -C "$_ps_dir/repo" config user.email t@t
        git -C "$_ps_dir/repo" config user.name t
        echo x > "$_ps_dir/repo/f"
        git -C "$_ps_dir/repo" add f
        git -C "$_ps_dir/repo" -c commit.gpgsign=false commit -qm init
        # PATH is given to the tmux SERVER (it resolved `pi` from the environment it
        # was started with) and to the fish that runs pwt — never exported here, so no
        # later check can find the stub on its own PATH.
        _ps_path="$_ps_dir/stub:$PATH"
        _ps_t() { tmux -S "$_ps_sock" "$@"; }
        _ps_run() { env TMUX="$_ps_sock" PATH="$_ps_path" PWT_FORWARD_ENV= \
            fish -N -c "source $_PWT; cd '$_ps_dir/repo'; pwt $1" >"$_ps_dir/out-$1" 2>&1; }
        env PATH="$_ps_path" tmux -S "$_ps_sock" -f /dev/null \
            new-session -d -s project -c "$_ps_dir/repo" 'sleep 300'
        _ps_t new-session -d -s scratch -c "$_ps_dir/elsewhere" 'sleep 300'
        _ps_run demo
        _ps_t list-panes -a -F '#{session_name}|#{window_name}' > "$_ps_dir/panes1"
        _ps_t list-sessions -F '#{session_name}' > "$_ps_dir/sess1"
        # Now a session standing IN that worktree. Its session_path is inside the tree,
        # so only an EXACT root match keeps it from claiming the next window. Named
        # `aaa` on purpose: `list-sessions` sorts by name, so a mutation that matched
        # in-tree would reach this session BEFORE the project one and the check would
        # catch it (named `wt` it sorted after, and the mutant still passed).
        _ps_t new-session -d -s aaa -c "$_ps_dir/repo/__worktrees/demo" 'sleep 300'
        _ps_run demo2
        _ps_t list-panes -a -F '#{session_name}|#{window_name}' > "$_ps_dir/panes2"
        # Tier 2: a session NAMED after the repo whose recorded start directory is
        # elsewhere. The caller's session is recreated LAST (see below) so that a
        # resolver with no name tier lands in `scratch` and this check notices — with
        # `repo` created last it was also the caller, and the check passed either way.
        _ps_t kill-session -t project
        _ps_t kill-session -t aaa
        _ps_t new-session -d -s repo -c "$_ps_dir/elsewhere" 'sleep 300'
        # No client is attached to this server, so tmux's "current" session is the one
        # most recently made active. Recreating the caller LAST is what makes that
        # deterministic — and both remaining checks depend on it, so if this ever
        # stops holding they fail loudly rather than pass quietly.
        _ps_t kill-session -t scratch
        _ps_t new-session -d -s scratch -c "$_ps_dir/elsewhere" 'sleep 300'
        _ps_run demo3
        _ps_t list-panes -a -F '#{session_name}|#{window_name}' > "$_ps_dir/panes3"
        # The prefix trap: with no session named `repo`, a bare (unanchored) name
        # target would answer from `repo2` instead of falling through to the caller.
        _ps_t kill-session -t repo
        _ps_t new-session -d -s repo2 -c "$_ps_dir/elsewhere" 'sleep 300'
        _ps_t kill-session -t scratch
        _ps_t new-session -d -s scratch -c "$_ps_dir/elsewhere" 'sleep 300'
        _ps_run demo4
        _ps_t list-panes -a -F '#{session_name}|#{window_name}' > "$_ps_dir/panes4"
        _ps_t list-sessions -F '#{session_name}' > "$_ps_dir/sess4"
        check "pwt: opens the workstream window in the repo's own session" \
            grep -qx 'project|demo' "$_ps_dir/panes1"
        check "pwt: leaves the caller's session alone" \
            bash -c '! grep -q "^scratch|demo$" "$1"' _ "$_ps_dir/panes1"
        check "pwt: creates no session of its own" \
            test "$(wc -l < "$_ps_dir/sess1" | tr -d ' ')" = 2
        check "pwt: a session sitting in the worktree never claims the window" \
            bash -c 'grep -qx "project|demo2" "$1" && ! grep -q "^aaa|demo2$" "$1"' \
            _ "$_ps_dir/panes2"
        check "pwt: a session named after the repo is the fallback home" \
            grep -qx 'repo|demo3' "$_ps_dir/panes3"
        check "pwt: falls back to the caller's session, not to a longer name" \
            bash -c 'grep -qx "scratch|demo4" "$1" && ! grep -q "^repo2|demo4$" "$1"' \
            _ "$_ps_dir/panes4"
        check "pwt: created no session anywhere along the way" \
            test "$(wc -l < "$_ps_dir/sess4" | tr -d ' ')" = 2
        # Snap-on-reuse, the scenario the feature exists for: spawn while NO session
        # owns the repo root (the window lands in the caller's), then bring that session
        # into existence and go to the workstream again. `zlast` is created LAST so the
        # client-less "current" session is NOT the project — otherwise a mutant that
        # moved the window to the current session instead of the resolved parent would
        # land in the right place and pass.
        _ps_t kill-session -t repo2
        _ps_run demo5
        _ps_t list-panes -a -F '#{session_name}|#{window_name}' > "$_ps_dir/panes5"
        _ps_t new-session -d -s proj -c "$_ps_dir/repo" 'sleep 300'
        _ps_t new-session -d -s zlast -c "$_ps_dir/elsewhere" 'sleep 300'
        _ps_t list-panes -a -F '#{window_name}|#{pane_id}' > "$_ps_dir/pane5before"
        _ps_run demo5
        _ps_t list-panes -a -F '#{session_name}|#{window_name}' > "$_ps_dir/panes6"
        _ps_t list-sessions -F '#{session_name}' > "$_ps_dir/sess6"
        _ps_t list-panes -a -F '#{window_name}|#{@pwt_sid}|#{@pwt_dir}|#{pane_pipe}' \
            > "$_ps_dir/meta6"
        _ps_t list-panes -a -F '#{window_name}|#{pane_id}' > "$_ps_dir/pane5after"
        _ps_run demo5
        _ps_t list-panes -a -F '#{session_name}|#{window_name}' > "$_ps_dir/panes7"
        # A pi started BY HAND inside a worktree carries no markers, so it is not a
        # workstream and must never be dragged across sessions — the reuse path finds
        # it through the pane-cwd fallback, which is exactly the dangerous door.
        git -C "$_ps_dir/repo" worktree add -q -b demo6 "$_ps_dir/repo/__worktrees/demo6"
        _ps_t new-window -dP -F '#{pane_id}' -t zlast: -n hand \
            -c "$_ps_dir/repo/__worktrees/demo6" \
            "printf '\\033]2;π - hand\\007'; exec sleep 300"
        _ps_run demo6
        _ps_t list-panes -a -F '#{session_name}|#{window_name}' > "$_ps_dir/panes8"
        check "pwt: a spawn with no project session falls back to the caller's" \
            grep -qx 'scratch|demo5' "$_ps_dir/panes5"
        check "pwt: going back to it afterwards moves it into the project session" \
            grep -qx 'proj|demo5' "$_ps_dir/panes6"
        check "pwt: the move does not go to the current session instead" \
            bash -c '! grep -q "^zlast|demo5$" "$1" && ! grep -q "^scratch|demo5$" "$1"' \
            _ "$_ps_dir/panes6"
        check "pwt: the moved window is the same workstream, tap intact" \
            grep -qE '^demo5\|repo-demo5\|.+\|1$' "$_ps_dir/meta6"
        # ...and the same PANE: a mutant that killed the window and reopened it with the
        # same markers would resume the transcript but drop the live pi.
        check "pwt: the move relocates the window, never respawns it" \
            bash -c 'a=$(grep "^demo5|" "$1"); b=$(grep "^demo5|" "$2"); [[ -n "$a" && "$a" = "$b" ]]' \
            _ "$_ps_dir/pane5before" "$_ps_dir/pane5after"
        check "pwt: moving created no session either" \
            test "$(wc -l < "$_ps_dir/sess6" | tr -d ' ')" = 3
        check "pwt: going to it again moves nothing and spawns nothing" \
            bash -c '[[ "$(grep -cx "proj|demo5" "$1")" = 1 && "$(grep -c demo5 "$1")" = 1 ]]' \
            _ "$_ps_dir/panes7"
        check "pwt: never drags a hand-started pi into the project session" \
            bash -c 'grep -q "^zlast|hand$" "$1" && ! grep -q "^proj|hand$" "$1"' \
            _ "$_ps_dir/panes8"
        _ps_t kill-server >/dev/null 2>&1
        rm -rf "$_ps_dir"
    else
        _skip "pwt: window placement (behavioural)" "tmux not installed"
    fi
else
    _skip "pwt: __worktrees ignore + pi preflight" "fish not installed"
fi

# ── tmux status wiring for the tap ───────────────────────────────────────────
_TMUXCONF="$DOTFILES/base/tmux/.config/tmux/tmux.conf"
# pi stays silent unless it is told the terminal supports OSC 7501, and tmux never
# answers that query.
check_has "tmux.conf: pi is told to report without feature detection" \
    'set-environment -g PI_PROGRAM_STATUS 1' "$_TMUXCONF"
check_has "tmux.conf: the window list carries the alert flag" \
    'window-status-format .*@pi_alert' "$_TMUXCONF"
# A push cannot be un-invented once it has fired, so it needs a switch that does not
# cost the ambient flag: the tap reads this at push time, so it mutes live.
check_has "tmux.conf: pushes are muted by one option, not by the flag" \
    'set -g @pwt_notify 1' "$_TMUXCONF"
# Hooks are tmux commands, not shell commands: a run-shell version needs $TMUX to
# find the server and silently clears nothing when it is absent.
check_has "tmux.conf: the flag decays when the pane is focused" \
    "set-hook -g pane-focus-in 'set-window-option -u @pi_alert'" "$_TMUXCONF"
check_has "tmux.conf: the flag decays on a window switch" \
    "set-hook -g after-select-window 'set-window-option -u @pi_alert'" "$_TMUXCONF"
check_not "tmux.conf: the decay hooks spawn no tmux client" \
    'run-shell .*@pi_alert' "$_TMUXCONF"
# Live (non-worktree) sessions are reached through the same window-finding code.
check_has "pwt: exposes a jump verb for live sessions" \
    'case jump' "$_PWT"
# The fish .gitignore is an allowlist: functions/* is ignored unless negated, so
# a new own-file silently drops out of the repo without this.
check_has "pwt: not gitignored (fish allowlist negation present)" \
    '^!functions/pwt\.fish' "$DOTFILES/base/fish/.config/fish/.gitignore"

# repo-list backs the C-f repo half. The rule is subtle enough to have been got
# wrong twice during development, so each branch is asserted directly.
_RL="$DOTFILES/base/tmux/bin/repo-list"
check "repo-list: helper exists in base/tmux/bin" test -f "$_RL"
check "repo-list: is executable" test -x "$_RL"
check "repo-list: shellcheck clean" shellcheck -S warning "$_RL"
check "repo-list: runs under /bin/bash (3.2 on macOS)" \
    env PWT_SRC="$DOTFILES/.git" /bin/bash "$_RL" --stdin < /dev/null
check "repo-list: keeps a repo root, drops its subdirectories" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT; cd "$d"; git init -q; mkdir -p sub/deep
        out=$(printf "%s\n%s\n%s\n" "$d" "$d/sub" "$d/sub/deep" | "$1" --stdin)
        [[ "$out" == "$d" ]]' _ "$_RL"
check "repo-list: keeps a path that is in no repo (nothing hidden)" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT; mkdir -p "$d/standalone"
        out=$(printf "%s\n" "$d/standalone" | "$1" --stdin)
        [[ "$out" == "$d/standalone" ]]' _ "$_RL"
check "repo-list: drops .git and __worktrees paths" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT; cd "$d"; git init -q
        out=$(printf "%s\n%s\n" "$d/.git" "$d/__worktrees/x" | "$1" --stdin)
        [[ -z "$out" ]]' _ "$_RL"
# The two navigation roots must not depend on zoxide still holding a score for
# them: a fresh PWT_SRC has no zoxide entries at all, so this exercises the
# always-emit path. Home first, source root last (outer -> inner).
check "repo-list: always offers ~ and the source root, in that order" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
        out=$(PWT_SRC="$d" "$1" 2>/dev/null)
        [[ "$(printf "%s\n" "$out" | head -1)" == "$HOME" ]] &&
        [[ "$(printf "%s\n" "$out" | tail -1)" == "$d" ]]' _ "$_RL"
check "repo-list: --stdin filters exactly the given list (no injection)" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
        out=$(printf "" | PWT_SRC="$d" "$1" --stdin)
        [[ -z "$out" ]]' _ "$_RL"
# --stdin must pass paths through untouched: skipping $HOME/$SRC there (they are
# skipped in zoxide mode to avoid re-emitting them) silently dropped input lines.
check "repo-list: --stdin passes the roots through unchanged" \
    bash -c 'out=$(printf "%s\n%s\n" "$HOME" "$1" | "$2" --stdin)
        [[ "$out" == "$HOME"$'"'"'\n'"'"'"$1" ]]' _ "$HOME/src" "$_RL"

# The picker is the navigation half of pwt (tmux C-w): it must derive the same
# session id pwt creates, and must not use bash-4-only builtins — a tmux popup's
# PATH can resolve to macOS's bash 3.2.
_PWT_PICK="$DOTFILES/base/tmux/bin/pwt-pick"
check "pwt-pick: picker exists in base/tmux/bin" test -f "$_PWT_PICK"
check "pwt-pick: is executable" test -x "$_PWT_PICK"
check "pwt-pick: shellcheck clean" shellcheck -S warning "$_PWT_PICK"
# TMUX is unset for every --list assertion: check.sh may itself run inside a tmux
# pane, and live-pane rows would then appear in the results and move `head -1`.
check "pwt-pick: --list runs under /bin/bash (3.2 on macOS)" \
    env -u TMUX PWT_SRC="$DOTFILES/.git" HOME=/nonexistent /bin/bash "$_PWT_PICK" --list
# Single source of truth: the panel creates and removes nothing itself, and no
# longer pins a session id — it asks pwt, which owns the worktree lifecycle.
check_has "pwt-pick: delegates lifecycle to pwt" \
    'fish -c' "$_PWT_PICK"
check_not "pwt-pick: does not pin a session id itself (pwt owns it)" \
    '\-\-session-id' "$_PWT_PICK"
# Both of these belong here rather than with the pwt assertions: $_PWT_PICK is not
# defined until this point in the file, and grep against an empty filename fails.
check_has "pwt-pick: reserves the new verb as a slug too" \
    'rm\|remove\|jump\|here\|help\|ls\|close\|reload' "$_PWT_PICK"
# C-x is one confirmation before the whole teardown, and a live row is closeable —
# nothing in the panel asks the user to type a command to finish the job.
check_has "pwt-pick: ctrl-x runs the confirmed teardown" \
    'rmstash' "$_PWT_PICK"
check_has "pwt-pick: ctrl-x can close a live workstream" \
    'run_pwt close' "$_PWT_PICK"
# ctrl-s is the reload key: unbound in fzf 0.73 (ctrl-l is clear-screen, ctrl-g/ctrl-q
# abort), and it reaches fzf through tmux — verified by sending it to a --expect panel
# on a private socket, because a key the terminal swallows looks like a broken bind.
check_has "pwt-pick: ctrl-s runs the in-place reload" \
    'ctrl-s' "$_PWT_PICK"
check_has "pwt-pick: reload is taken off the editor via --expect" \
    '--expect=ctrl-t,ctrl-x,ctrl-r,ctrl-s' "$_PWT_PICK"
check_not "pwt-pick: ctrl-l stays fzf's clear-screen key" \
    'expect=.*ctrl-l' "$_PWT_PICK"
# The confirmation mirrors ctrl-x's: the kill is one y/N away, and the semantic guard
# (a mid-turn agent needs --force) stays in pwt, which keeps the popup open on a
# refusal — the panel must not re-implement or pre-empt it.
check_has "pwt-pick: reload asks once before restarting pi" \
    'Reload the pi at' "$_PWT_PICK"
check_has "pwt-pick: reload delegates to pwt reload" \
    'run_pwt reload' "$_PWT_PICK"
check_has "pwt-pick: the panel header names the reload key" \
    'ctrl-s reload' "$_PWT_PICK"
check_has "pwt: the doc lists the panel's reload key" \
    'ctrl-s' "$DOTFILES/docs/PWT.md"
check_has "pwt-pick: labels a row from the window marker when present" \
    '@pwt_label' "$_PWT_PICK"
# A repo with no workstreams has no row, so the list cannot reach it; and not every
# repo can take a worktree. This is the way in for both.
check_has "pwt-pick: reaches a repo with no rows through repo-list" \
    'repo-list' "$_PWT_PICK"
check_has "pwt-pick: that stage can create the in-place rung too" \
    'run_pwt here' "$_PWT_PICK"
# The query is never fed to fzf as a command string: it is free text, and that is the
# injection this whole design exists to avoid.
check_not "pwt-pick: never interpolates the typed query into a command" \
    '{q}' "$_PWT_PICK"
check_has "pwt-pick: shows the state pi reports" \
    '@pi_state' "$_PWT_PICK"
# An fzf execute()/reload() bind interpolates the row and whatever was typed into
# a COMMAND STRING that a shell then parses, so a quote in a path is an injection.
# --expect delivers the key and the row on stdout, to be passed as argv instead.
# --expect TAKES the key away from fzf's line editor, so the verbs must be keys the
# editor does not use: ctrl-n/ctrl-p are its next/previous-match pair and ctrl-d is
# delete-char/eof. Binding those made ctrl-p navigate while ctrl-n exited the panel.
check_has "pwt-pick: takes its verbs from --expect, off the editor's keys" \
    '--expect=ctrl-t,ctrl-x,ctrl-r' "$_PWT_PICK"
check_not "pwt-pick: no longer steals the fzf navigation keys" \
    '--expect=ctrl-n' "$_PWT_PICK"
# Every live pi pane is adopted as the panel opens — the ones pwt opened are an
# idempotent re-attach (plain pipe-pane replaces), a hand-started session gets its
# only attach. Twin of the pwt.fish assertion: #{pane_id} is the only safe channel,
# because the command string passes through strftime before tmux expands formats.
check_has "pwt-pick: adopts every live pi pane when the panel opens" \
    'pwt-osc #\{pane_id\}' "$_PWT_PICK"
# The query is offered as the default name, which is the whole point of
# --print-query: you typed the name while filtering, so the prompt must not make you
# type it twice.
check_has "pwt-pick: offers the typed query as the default workstream name" \
    '\-\-print-query' "$_PWT_PICK"
check_has "pwt-pick: an empty answer accepts that default" \
    'slug="\$query"' "$_PWT_PICK"
# "Do I still need this?" — status --branch cannot answer it for a branch with no
# upstream, so the preview also shows the commits that exist on no remote. It is a
# SCRIPT, not an inline snippet: fzf runs previews with `$SHELL -c` and $SHELL is fish,
# where `n=$(…)` is a syntax error printed into the pane. Pinned here so an inline
# snippet cannot creep back.
_PWT_PREVIEW="$DOTFILES/base/tmux/bin/pwt-preview"
check "pwt-preview: helper exists in base/tmux/bin" test -f "$_PWT_PREVIEW"
check "pwt-preview: is executable" test -x "$_PWT_PREVIEW"
check "pwt-preview: shellcheck clean" shellcheck -S warning "$_PWT_PREVIEW"
# A popup's PATH can resolve to macOS's bash 3.2, and this runs from a keypress.
check "pwt-preview: runs under /bin/bash (3.2 on macOS)" \
    /bin/bash "$_PWT_PREVIEW" "$DOTFILES"
# A live row can be a pi started in $HOME or /tmp: no repo, so say so instead of
# rendering an empty preview that reads as broken.
check "pwt-preview: names a non-repository row instead of rendering nothing" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
        out=$("$1" "$d" 2>&1); [[ "$out" == *"not a git work tree"* ]]' \
    _ "$_PWT_PREVIEW"
check_has "pwt-preview: shows commits on no remote" \
    '\-\-not \-\-remotes' "$_PWT_PREVIEW"
check_has "pwt-pick: the preview is a script, not a shell snippet" \
    'pwt-preview \{2\}' "$_PWT_PICK"
check_not "pwt-pick: no inline preview snippet" \
    'rev-list' "$_PWT_PICK"
# Behaviour through the shell that broke it: fish. A script with a shebang is
# unaffected by $SHELL; the same snippet inline was not.
check "pwt-preview: renders correctly when invoked from fish" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT; cd "$d"; git init -q repo; cd repo
        git config user.email t@t; git config user.name t; echo x > f; git add f
        git -c commit.gpgsign=false commit -qm init
        out=$(fish -c "\"$1\" \"$PWD\"" 2>&1)
        grep -q "^## " <<<"$out" && grep -q "commit(s) on no remote" <<<"$out" &&
        ! grep -q "Unsupported use" <<<"$out"' \
    _ "$_PWT_PREVIEW"
# ...and neither list format may ever emit an EMPTY field: `read` collapses one and
# shifts every later column, so the tap would skip exactly the panes that have no
# state yet — the untapped ones, i.e. the whole point of the adoption. grep -F: the
# pattern is a tmux format, all braces and question marks.
check "pwt-pick: emits a placeholder, never an empty state field" \
    grep -qF -- '#{?#{@pi_state},#{@pi_state},-}' "$_PWT_PICK"
check_not "pwt-pick: builds no shell command string for fzf" \
    '\-\-bind' "$_PWT_PICK"
# pi panes are found by window TITLE, because pane_current_command is `node` for
# pi and for every other node program. tmux also reports RESOLVED paths while find
# does not, so without canonicalisation the ▸ marker silently disappears.
check_has "pwt-pick: identifies pi panes by window title" \
    'pane_title' "$_PWT_PICK"
check_has "pwt-pick: canonicalises paths before comparing" \
    'pwd -P' "$_PWT_PICK"
# The prefix is needed in BOTH files — pwt decides whether a window is worth
# reusing, the panel decides which panes are pi — so a rename must not be able to
# update one and miss the other. The default is read from pwt-pick and asserted in
# pwt, which fails if either side moves alone.
_pi_pref="$(sed -n 's/.*PWT_PI_TITLE:-\(.*\)}.*/\1/p' "$_PWT_PICK" | head -1)"
check "pwt-pick: declares a default pi window-title prefix" test -n "$_pi_pref"
check "pwt: uses the same pi window-title prefix as pwt-pick" \
    grep -qF -- "$_pi_pref" "$_PWT"
# display-popup -E closes as soon as the command exits, so a refusal or a
# validation error has to hold the popup open or it is unreadable.
check_has "pwt-pick: holds the popup open when pwt fails" \
    'press enter' "$_PWT_PICK"

# `pwt ls` is the shell-side half of the panel: same rows, same order, ONE
# implementation (pwt-pick --list). Outside tmux every marker is blank, which is
# what makes it usable from a script.
check_has "pwt: exposes a shell-side listing verb" \
    'case ls' "$_PWT"
if command -v fish >/dev/null 2>&1; then
    _pwt_ls_tmp="$(mktemp -d)"
    mkdir -p "$_pwt_ls_tmp/org/repo/__worktrees/demo"
    check "pwt: ls prints the panel's rows outside tmux" \
        bash -c 'out=$(env -u TMUX PWT_SRC="$1" HOME=/nonexistent PWT_PICK="$2" "$3" -N -c "source $4; pwt ls")
            grep -qF "org/repo/demo" <<<"$out"' \
        _ "$_pwt_ls_tmp" "$_PWT_PICK" "$(command -v fish)" "$_PWT"
    rm -rf "$_pwt_ls_tmp"
fi

# Completions live in base/fish/completions, which the fish .gitignore ignores by
# default: the allowlist negation is the load-bearing part, same trap as functions/.
_PWT_COMP="$DOTFILES/base/fish/.config/fish/completions/pwt.fish"
check "pwt completions: file exists in base/fish" test -f "$_PWT_COMP"
check_has "pwt completions: not gitignored (allowlist negation present)" \
    '^!completions/pwt\.fish' "$DOTFILES/base/fish/.config/fish/.gitignore"
if command -v fish >/dev/null 2>&1; then
    check "pwt completions: parses (fish -n)" fish -n "$_PWT_COMP"
    # Behaviour, not text: complete -C is the same engine TAB uses.
    check "pwt completions: offer verbs and this repo's workstream slugs" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT; cd "$d"; git init -q repo; cd repo
            mkdir -p __worktrees/demo
            out=$(fish -N -c "source $1; complete -C \"pwt \"; complete -C \"pwt rm \"")
            grep -q "^ls" <<<"$out" && grep -q "^demo" <<<"$out"' \
        _ "$_PWT_COMP"
fi

# End-to-end listing: a fabricated worktree must surface as org/repo/slug behind a
# two-column marker (▸ window open / ● pi history). With no tmux and a missing
# HOME both markers are blank, which also pins the column layout.
_pwt_tmp="$(mktemp -d)"
mkdir -p "$_pwt_tmp/org/repo/__worktrees/demo" "$_pwt_tmp/org/repo/__worktrees/demo/sub" "$_pwt_tmp/org/live"
check "pwt-pick: lists a worktree as org/repo/slug" \
    bash -c '[[ "$(env -u TMUX PWT_SRC="$1" HOME=/nonexistent "$2" --list | head -1 | cut -f1)" == "    org/repo/demo" ]]' \
    _ "$_pwt_tmp" "$_PWT_PICK"

# Live pi panes and the ▸ marker without a real tmux server: a stub on PATH
# answers the two format queries the picker makes, so no session of the
# developer's is involved and the result is deterministic.
_pwt_bin="$(mktemp -d)"
cat > "$_pwt_bin/tmux" <<'STUB'
#!/bin/bash
case "$*" in
  *pane_title*)        printf '%s\t%s\t%s\t%s\t%s\n' "$PWT_STUB_TITLE" "$PWT_STUB_LIVE" "${PWT_STUB_LABEL:--}" "${PWT_STUB_STATE:--}" "%9" ;;
  *pane_current_path*) printf '%s\t%s\n' "$PWT_STUB_WT" "$PWT_STUB_WTSTATE" ;;
  *pipe-pane*)         printf '%s\n' "$*" >> "$PWT_STUB_PIPELOG" ;;
esac
STUB
chmod +x "$_pwt_bin/tmux"
check "pwt-pick: marks a worktree whose window is open and lists live pi panes" \
    bash -c 'out=$(env TMUX=stub PATH="$1:$PATH" PWT_SRC="$2" HOME=/nonexistent \
        PWT_STUB_TITLE="π - main" PWT_STUB_WT="$2/org/repo/__worktrees/demo" \
        PWT_STUB_LIVE="$2/org/live" "$3" --list)
        grep -qF "▸   org/repo/demo" <<<"$out" && grep -qF "▸   org/live" <<<"$out"' \
    _ "$_pwt_bin" "$_pwt_tmp" "$_PWT_PICK"
check "pwt-pick: a pi pane inside a worktree is not listed twice" \
    bash -c 'out=$(env TMUX=stub PATH="$1:$PATH" PWT_SRC="$2" HOME=/nonexistent \
        PWT_STUB_TITLE="π - main" PWT_STUB_WT="$2/org/repo/__worktrees/demo" \
        PWT_STUB_LIVE="$2/org/repo/__worktrees/demo" "$3" --list)
        [[ "$(grep -c . <<<"$out")" == "1" ]]' \
    _ "$_pwt_bin" "$_pwt_tmp" "$_PWT_PICK"
check "pwt-pick: labels a marked window by its workstream, not its directory" \
    bash -c 'out=$(env TMUX=stub PATH="$1:$PATH" PWT_SRC="$2" HOME=/nonexistent \
        PWT_STUB_TITLE="π - x" PWT_STUB_WT=/nonexistent-wt PWT_STUB_LIVE="$2/org/live" \
        PWT_STUB_LABEL="audit" "$3" --list)
        grep -qF "▸   audit" <<<"$out" && ! grep -qF "▸   org/live" <<<"$out"' \
    _ "$_pwt_bin" "$_pwt_tmp" "$_PWT_PICK"
# The ▸ marker and the live-row suppression must use the SAME rule (a pane anywhere
# beneath the worktree), or a pi that cd'd into a subdirectory hides its own row and
# leaves the worktree row unmarked: the open state disappears from the panel.
check "pwt-pick: a pane in a subdirectory still marks the worktree row open" \
    bash -c 'out=$(env TMUX=stub PATH="$1:$PATH" PWT_SRC="$2" HOME=/nonexistent \
        PWT_STUB_TITLE="π - x" PWT_STUB_WT="$2/org/repo/__worktrees/demo/sub" \
        PWT_STUB_LIVE="$2/org/repo/__worktrees/demo/sub" "$3" --list)
        grep -qF "▸   org/repo/demo" <<<"$out" && [[ "$(grep -c . <<<"$out")" == "1" ]]' \
    _ "$_pwt_bin" "$_pwt_tmp" "$_PWT_PICK"
# The adoption itself: an EMPTY state is the untapped pane this exists for, and the
# panel must still attach to it. The stub answers the row/state queries the way the
# real formats do (a `-` placeholder), and records pipe-pane.
check "pwt-pick: --tap-live adopts a pane that has no state yet" \
    bash -c 'log=$(mktemp); trap "rm -f \"$log\"" EXIT
        env TMUX=stub PATH="$1:$PATH" PWT_SRC="$2" HOME=/nonexistent \
            PWT_STUB_TITLE="π - x" PWT_STUB_LIVE="$2/org/live" PWT_STUB_STATE="" \
            PWT_STUB_PIPELOG="$log" "$3" --tap-live || exit 1
        grep -qF "pipe-pane -t %9" "$log" && grep -qF "pwt-osc #{pane_id}" "$log"' \
    _ "$_pwt_bin" "$_pwt_tmp" "$_PWT_PICK"
# ...and the query seam stays a query: --list must attach nothing, or check.sh and
# every script that lists would mutate the developer's server.
check "pwt-pick: --list never attaches a tap" \
    bash -c 'log=$(mktemp); trap "rm -f \"$log\"" EXIT
        env TMUX=stub PATH="$1:$PATH" PWT_SRC="$2" HOME=/nonexistent \
            PWT_STUB_TITLE="π - x" PWT_STUB_LIVE="$2/org/live" \
            PWT_STUB_PIPELOG="$log" "$3" --list >/dev/null || exit 1
        [[ ! -s "$log" ]]' \
    _ "$_pwt_bin" "$_pwt_tmp" "$_PWT_PICK"
# pi's own state, and the ordering that makes the list answer "which one wants me"
# without reading it: a blocked workstream sorts above a working one.
check "pwt-pick: shows pi's state and floats a blocked workstream to the top" \
    bash -c 'out=$(env TMUX=stub PATH="$1:$PATH" PWT_SRC="$2" HOME=/nonexistent \
        PWT_STUB_TITLE="π - x" PWT_STUB_WT="$2/org/repo/__worktrees/demo" PWT_STUB_WTSTATE=blocked \
        PWT_STUB_LIVE="$2/org/live" PWT_STUB_STATE=working "$3" --list)
        [[ "$(printf "%s\n" "$out" | head -1 | cut -f1)" == "▸ ⚑ org/repo/demo" ]] &&
        printf "%s\n" "$out" | grep -qF "◐ org/live"' \
    _ "$_pwt_bin" "$_pwt_tmp" "$_PWT_PICK"
rm -rf "$_pwt_tmp" "$_pwt_bin"

# ── pwt window resolution (behavioural, not textual) ─────────────────────────
# Every pwt assertion above is a grep, and three live-probed bugs passed all of
# them: `pwt jump` landing on a plain shell, `pwt rm` missing a pi that had cd'd
# into a subdirectory of the worktree, and the lookup missing pi in a split that
# was not the active pane. These run the real lookups against a PRIVATE tmux
# server (-f /dev/null, own socket), so nothing the developer is running is
# touched and no fixture repo is left behind.
if command -v tmux >/dev/null 2>&1 && command -v fish >/dev/null 2>&1; then
    _pwtsock="$(mktemp -d)/sock"
    _pwt_repo="$(mktemp -d)/repo"
    _pwt_wt="$_pwt_repo/__worktrees/demo"
    mkdir -p "$_pwt_repo"
    (cd "$_pwt_repo" && git init -q && git -c commit.gpgsign=false config commit.gpgsign false \
        && git config user.email t@t && git config user.name t \
        && echo x > f && git add f && git -c commit.gpgsign=false commit -qm init \
        && git worktree add -q "$_pwt_wt") >/dev/null 2>&1
    # A stub `pi` makes window creation deterministic everywhere: every pane pwt
    # spawns stays alive (so "a window was opened" is observable without leaning on
    # remain-on-exit), and no test spawns the real one. It must be exported because
    # the tmux server inherits the PATH — and every probe below runs `fish -N`, because
    # this repo's config moves ~/.local/bin (where the real pi lives) back to the front
    # of PATH, which would silently undo the stub. PATH is restored before the block
    # ends so later sections see the real one.
    _pwt_stub="$(mktemp -d)"
    _pwt_envlog="$(mktemp)"
    # The stub records the RELOAD_PROBE value it was handed, so the reload test can
    # prove the -e arguments reached the process instead of merely appearing in the
    # command pwt printed. PWT_STUB_ENV_OUT must be exported BEFORE the server starts:
    # a respawned command inherits the SERVER's environment, not the caller's.
    cat > "$_pwt_stub/pi" <<'STUB'
#!/bin/sh
[ -n "$PWT_STUB_ENV_OUT" ] && printf '%s' "${RELOAD_PROBE:-}" >> "$PWT_STUB_ENV_OUT"
exec sleep 300
STUB
    chmod +x "$_pwt_stub/pi"
    PWT_STUB_ENV_OUT="$_pwt_envlog"; export PWT_STUB_ENV_OUT
    _pwt_path_saved="$PATH"
    PATH="$_pwt_stub:$PATH"; export PATH
    # pi cd'd into a SUBDIRECTORY of the worktree, in a window whose active pane is
    # therefore not the pane we are looking for either way. The panes run `sleep`,
    # not a shell: a shell rewrites its own pane title on every prompt (fish sets
    # "<cwd> - fish"), which would wipe the `π - ` title select-pane -T just set.
    # The title is a faithful stand-in for pi, which sets it once and keeps it
    # because it stays the foreground program.
    mkdir -p "$_pwt_wt/sub"
    # remain-on-exit is belt-and-braces under the stub: if a pane's command exits at
    # once (a stub that could not be found), tmux takes the window with it and "a
    # window was opened" would read as a failure that has nothing to do with the reuse
    # decision under test.
    tmux -S "$_pwtsock" -f /dev/null new-session -d -s pwttest -c /tmp "sleep 300" >/dev/null 2>&1
    tmux -S "$_pwtsock" set-option -g remain-on-exit on
    tmux -S "$_pwtsock" new-window -t pwttest -n pisub -c "$_pwt_wt/sub" "sleep 300" >/dev/null 2>&1
    _pwt_p1="$(tmux -S "$_pwtsock" list-panes -t pisub -F '#{pane_id}')"
    tmux -S "$_pwtsock" select-pane -t "$_pwt_p1" -T 'π - demo' >/dev/null 2>&1
    # A non-pi window and a pi window in the SAME directory, to pin which one jump
    # picks: the plain one keeps tmux's default pane title.
    tmux -S "$_pwtsock" new-window -t pwttest -n otheratroot -c "$_pwt_repo" "sleep 300" >/dev/null 2>&1
    tmux -S "$_pwtsock" new-window -t pwttest -n piatroot -c "$_pwt_repo" "sleep 300" >/dev/null 2>&1
    _pwt_p3="$(tmux -S "$_pwtsock" list-panes -t piatroot -F '#{pane_id}')"
    tmux -S "$_pwtsock" select-pane -t "$_pwt_p3" -T 'π - root' >/dev/null 2>&1

    _pwtprobe="$(mktemp)"
    cat > "$_pwtprobe" <<'PROBE'
source $argv[1]/base/fish/.config/fish/functions/pwt.fish
switch $argv[2]
    case find
        echo (__pwt_window_for $argv[3] $argv[4..-1])
    case rm
        cd $argv[3]; and pwt rm $argv[4]
    case rmstash
        cd $argv[3]; and pwt rm --stash $argv[4]
    case close
        pwt close $argv[3]
    case jump
        pwt jump $argv[3]
    case ws
        echo (__pwt_workstream_window $argv[3] $argv[4])
    case open
        __pwt_open_window $argv[3] $argv[4] $argv[5] $argv[6]
    case here
        cd $argv[3]; and pwt here $argv[4] $argv[5]
    case reload
        pwt reload $argv[3..-1]
end
PROBE

    check "pwt: finds pi in a SUBDIRECTORY of the worktree (in-tree)" \
        bash -c '[[ -n "$(env TMUX="$1" fish -N "$2" "$3" find "$4" in-tree)" ]]' \
        _ "$_pwtsock" "$_pwtprobe" "$DOTFILES" "$_pwt_wt"
    check "pwt: an exact-only lookup does not match that pane (documented limit)" \
        bash -c '[[ -z "$(env TMUX="$1" fish -N "$2" "$3" find "$4" pi-only)" ]]' \
        _ "$_pwtsock" "$_pwtprobe" "$DOTFILES" "$_pwt_wt"
    check "pwt: rm refuses while a pi pane sits inside the worktree" \
        bash -c 'env TMUX="$1" fish -N "$2" "$3" rm "$4" demo >/dev/null 2>&1
            [[ -d "$4/__worktrees/demo" ]]' \
        _ "$_pwtsock" "$_pwtprobe" "$DOTFILES" "$_pwt_repo"
    # The control matters as much as the refusal: a guard that refuses everything
    # would pass the test above while making `pwt rm` useless.
    check "pwt: rm still removes a worktree no window holds (positive control)" \
        bash -c 'cd "$4" && git worktree add -q __worktrees/solo >/dev/null 2>&1
            env TMUX="$1" fish -N "$2" "$3" rm "$4" solo >/dev/null 2>&1
            [[ ! -d "$4/__worktrees/solo" ]]' \
        _ "$_pwtsock" "$_pwtprobe" "$DOTFILES" "$_pwt_repo"
    check "pwt: jump picks the pi window, not a shell in the same directory" \
        bash -c 'env TMUX="$1" fish -N "$2" "$3" jump "$4" >/dev/null 2>&1
            tmux -S "$1" list-windows -t pwttest -F "#{window_active}:#{pane_title}" | grep -q "^1:π - "' \
        _ "$_pwtsock" "$_pwtprobe" "$DOTFILES" "$_pwt_repo"

    # TWO in-place workstreams in ONE repo: same directory, different workstreams.
    # Nothing about the cwd separates them, which is exactly why the window carries
    # @pwt_sid — matching on the path would send both to the first window, and a
    # second pi on that window's session id clobbers its transcript.
    tmux -S "$_pwtsock" new-window -t pwttest -n inplace-a -c "$_pwt_repo" "sleep 300"
    tmux -S "$_pwtsock" new-window -t pwttest -n inplace-b -c "$_pwt_repo" "sleep 300"
    _in_a="$(tmux -S "$_pwtsock" list-windows -t pwttest -F '#{window_id} #{window_name}' \
        | awk '$2=="inplace-a"{print $1}')"
    _in_b="$(tmux -S "$_pwtsock" list-windows -t pwttest -F '#{window_id} #{window_name}' \
        | awk '$2=="inplace-b"{print $1}')"
    tmux -S "$_pwtsock" set-window-option -t "$_in_a" @pwt_sid repo-alpha
    tmux -S "$_pwtsock" set-window-option -t "$_in_b" @pwt_sid repo-beta
    check "pwt: tells two in-place workstreams in one directory apart" \
        bash -c '[[ "$(env TMUX="$1" fish -N "$2" "$3" ws repo-alpha "$6")" == "$4" && \
                  "$(env TMUX="$1" fish -N "$2" "$3" ws repo-beta "$6")" == "$5" ]]' \
        _ "$_pwtsock" "$_pwtprobe" "$DOTFILES" "$_in_a" "$_in_b" "$_pwt_repo"
    # The second `pwt here` must JUMP to that window, not open a second one on the
    # only working tree there is — and it needs no pi to prove it, since reuse never
    # spawns one.
    _in_before="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    _in_out="$(env TMUX="$_pwtsock" fish -N "$_pwtprobe" "$DOTFILES" here "$_pwt_repo" alpha 2>&1)"
    _in_after="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    check "pwt: 'here' jumps to the existing in-place workstream, opening no window" \
        bash -c '[[ "$1" == "$2" && "$3" == *"jumped to the open window"* ]]' \
        _ "$_in_before" "$_in_after" "$_in_out"
    check "pwt: 'here' rejects a base ref (nothing to base a worktree on)" \
        bash -c 'cd "$4" && ! env TMUX="$1" fish -N "$2" "$3" here alpha develop >/dev/null 2>&1' \
        _ "$_pwtsock" "$_pwtprobe" "$DOTFILES" "$_pwt_repo"
    # A second, DIFFERENT in-place label in the same repo must get its own window.
    # This is the regression the path fallback caused: the lookup found alpha's window
    # (same directory) and jumped to it, so the new label never became a workstream at
    # all and the jump still looked like success. `gamma` deliberately does not appear
    # in the fixtures above, which already claim repo-alpha and repo-beta. This is the
    # one assertion that spawns pi — which need not be installed, since remain-on-exit
    # keeps the window either way.
    check "pwt: a second in-place label gets its own window, not the first one's" \
        bash -c 'env TMUX="$1" fish -N "$2" "$3" here "$4" gamma >/dev/null 2>&1
            tmux -S "$1" list-windows -t pwttest -F "#{window_name}|#{pane_start_command}" \
                | grep -q "^gamma|pi --session-id repo-gamma"' \
        _ "$_pwtsock" "$_pwtprobe" "$DOTFILES" "$_pwt_repo"

    # Identity is sid AND dir. The basename-derived sid is not unique — `here demo`
    # and a worktree `demo` in one repo share it, as do two repos with one name — and
    # the lookup is server-wide. Matching on the sid alone created the worktree, then
    # jumped into the OTHER workstream and reported success.
    tmux -S "$_pwtsock" new-window -t pwttest -n hereclash -c "$_pwt_repo" "sleep 300"
    _clash_w="$(tmux -S "$_pwtsock" list-windows -t pwttest -F '#{window_id} #{window_name}' \
        | awk '$2=="hereclash"{print $1}')"
    tmux -S "$_pwtsock" set-window-option -t "$_clash_w" @pwt_sid repo-demo
    tmux -S "$_pwtsock" set-window-option -t "$_clash_w" @pwt_dir "$(cd "$_pwt_repo" && pwd -P)"
    _clash_before="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    env TMUX="$_pwtsock" fish -N "$_pwtprobe" "$DOTFILES" open "$_pwt_wt" demo repo-demo >/dev/null 2>&1 || true
    _clash_after="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    check "pwt: same sid in a different dir gets its own window (here vs worktree)" \
        bash -c '[[ "$1" -lt "$2" ]]' _ "$_clash_before" "$_clash_after"
    # ...and a window opened before @pwt_dir existed is still reused, so the fix
    # cannot orphan a live workstream. The in-place assertions above already exercise
    # this tier: they mark @pwt_sid only.
    tmux -S "$_pwtsock" new-window -t pwttest -n legacy -c "$_pwt_repo" "sleep 300"
    _legacy_w="$(tmux -S "$_pwtsock" list-windows -t pwttest -F '#{window_id} #{window_name}' \
        | awk '$2=="legacy"{print $1}')"
    tmux -S "$_pwtsock" set-window-option -t "$_legacy_w" @pwt_sid repo-legacy
    _legacy_before="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    _legacy_out="$(env TMUX="$_pwtsock" fish -N "$_pwtprobe" "$DOTFILES" open "$_pwt_repo" legacy repo-legacy 2>&1)"
    _legacy_after="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    check "pwt: a window without @pwt_dir is still reused (pre-marker fallback)" \
        bash -c '[[ "$1" == "$2" && "$3" == *"jumped to the open window"* ]]' \
        _ "$_legacy_before" "$_legacy_after" "$_legacy_out"
    # ...but only when that window's panes are actually IN the workstream's tree. A
    # legacy `here` window (unmarked, cwd = repo root) must not be handed to the
    # same-named WORKTREE: that created the worktree, jumped into the main checkout
    # and reported success.
    tmux -S "$_pwtsock" new-window -t pwttest -n legacyother -c "$_pwt_repo" "sleep 300"
    _lother_w="$(tmux -S "$_pwtsock" list-windows -t pwttest -F '#{window_id} #{window_name}' \
        | awk '$2=="legacyother"{print $1}')"
    tmux -S "$_pwtsock" set-window-option -t "$_lother_w" @pwt_sid repo-other
    _lother_before="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    env TMUX="$_pwtsock" fish -N "$_pwtprobe" "$DOTFILES" open "$_pwt_wt" other repo-other >/dev/null 2>&1 || true
    _lother_after="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    check "pwt: an unmarked window elsewhere in the repo is NOT reused for a worktree" \
        bash -c '[[ "$1" -lt "$2" ]]' _ "$_lother_before" "$_lother_after"
    # A legacy window whose original pane sits in a NON-ACTIVE split: the plain
    # window formats report the ACTIVE pane's cwd, so a window-keyed lookup sees the
    # wrong directory. `here` is identity-only and has no path fallback behind it, so
    # that miss would open a SECOND pi on one session id — the transcript clobber.
    tmux -S "$_pwtsock" new-window -t pwttest -n legacysplit -c /tmp "sleep 300"
    tmux -S "$_pwtsock" split-window -t legacysplit -c "$_pwt_repo" "sleep 300"
    _split_main="$(tmux -S "$_pwtsock" list-panes -t legacysplit -F '#{pane_id}' | head -1)"
    tmux -S "$_pwtsock" select-pane -t "$_split_main"
    _split_w="$(tmux -S "$_pwtsock" list-windows -t pwttest -F '#{window_id} #{window_name}' \
        | awk '$2=="legacysplit"{print $1}')"
    tmux -S "$_pwtsock" set-window-option -t "$_split_w" @pwt_sid repo-split
    _split_before="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    _split_out="$(env TMUX="$_pwtsock" fish -N "$_pwtprobe" "$DOTFILES" here "$_pwt_repo" split 2>&1)"
    _split_after="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    check "pwt: a legacy window is found through a pane that is not its active one" \
        bash -c '[[ "$1" == "$2" && "$3" == *"jumped to the open window"* ]]' \
        _ "$_split_before" "$_split_after" "$_split_out"

    # Tier 1, positively: a window pwt marked with sid AND dir (gamma, above) is
    # reused without opening a second window — the case that would otherwise start a
    # second pi on one session id.
    _tier_before="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    _tier_out="$(env TMUX="$_pwtsock" fish -N "$_pwtprobe" "$DOTFILES" open "$_pwt_repo" gamma repo-gamma 2>&1)"
    _tier_after="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    check "pwt: a window marked with sid AND dir is reused" \
        bash -c '[[ "$1" == "$2" && "$3" == *"jumped to the open window"* ]]' \
        _ "$_tier_before" "$_tier_after" "$_tier_out"
    # A worktree with no branch (detached): `branch -d` has nothing to delete, which
    # is finished rather than failed — it must not print a "not found" error or claim
    # a "kept" branch, and the worktree must actually be gone.
    (cd "$_pwt_repo" && git worktree add --detach -q "$_pwt_repo/__worktrees/detached" >/dev/null 2>&1)
    check "pwt: rm fixture for a branchless worktree exists" test -d "$_pwt_repo/__worktrees/detached"
    _detached_out="$(env TMUX="$_pwtsock" fish -N "$_pwtprobe" "$DOTFILES" rm "$_pwt_repo" detached 2>&1)"
    _detached_rc=$?
    check "pwt: rm of a branchless worktree succeeds and mentions no branch" \
        bash -c '[[ "$1" -eq 0 && "$2" != *"not fully merged"* && "$2" != *"not found"* ]]' \
        _ "$_detached_rc" "$_detached_out"
    check "pwt: rm of a branchless worktree removed it" \
        test ! -d "$_pwt_repo/__worktrees/detached"

    # `rm --stash` is what C-x runs: close the window, keep the work, remove the tree.
    # The order matters and is asserted as a whole — a teardown that loses a `.env` or
    # a piece of uncommitted work is the failure mode this exists to prevent.
    (cd "$_pwt_repo" && git worktree add -q -b stashme "$_pwt_repo/__worktrees/stashme") >/dev/null 2>&1
    _stash_wt="$_pwt_repo/__worktrees/stashme"
    # .env must be IGNORED for the parking path: untracked-but-not-ignored goes to the
    # stash instead, which is a different assertion.
    (cd "$_stash_wt" && printf '.env\n' > .gitignore && echo y > g && git add .gitignore g \
        && git -c commit.gpgsign=false commit -qm wip \
        && echo change >> f && printf 'SECRET=1\n' > .env) >/dev/null 2>&1
    tmux -S "$_pwtsock" new-window -t pwttest -n stashme -c "$_stash_wt" "sleep 300" >/dev/null 2>&1
    _stash_pane="$(tmux -S "$_pwtsock" list-panes -t stashme -F '#{pane_id}' | head -1)"
    tmux -S "$_pwtsock" select-pane -t "$_stash_pane" -T 'π - stashme'
    _stash_before="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    _stash_out="$(env TMUX="$_pwtsock" fish -N "$_pwtprobe" "$DOTFILES" rmstash "$_pwt_repo" stashme 2>&1)"
    _stash_after="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    check "pwt: rm --stash closes the window and removes the tree" \
        bash -c '[[ "$1" -gt "$2" && ! -d "$3" ]]' \
        _ "$_stash_before" "$_stash_after" "$_stash_wt"
    check "pwt: rm --stash stashes uncommitted work onto the repo's list" \
        bash -c 'git -C "$1" stash list | grep -q "pwt: removed stashme"' _ "$_pwt_repo"
    check "pwt: rm --stash parks ignored files outside the tree" \
        bash -c 'd="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)/pwt-removed"
            ls -d "$d"/stashme-* >/dev/null 2>&1 && grep -q SECRET "$d"/stashme-*/.env' \
        _ "$_pwt_repo"
    check "pwt: rm --stash keeps an unmerged branch" \
        bash -c 'git -C "$1" show-ref --verify --quiet refs/heads/stashme' _ "$_pwt_repo"
    check "pwt: rm --stash reports what it preserved" \
        bash -c '[[ "$1" == *"uncommitted changes stashed"* && "$1" == *"ignored entr"* && "$1" == *"closed window"* ]]' \
        _ "$_stash_out"
    # ...and the plain form still refuses, with the stash path named as the way out.
    check "pwt: bare rm refuses and points at --stash" \
        bash -c 'cd "$1" && git worktree add -q -b refuser "$1/__worktrees/refuser" >/dev/null 2>&1
            printf "KEYS=1\n" > "$1/__worktrees/refuser/.env"
            out=$(env TMUX="$2" fish -N "$3" "$4" rm "$1" refuser 2>&1) || true
            [[ "$out" == *"--stash"* ]]' \
        _ "$_pwt_repo" "$_pwtsock" "$_pwtprobe" "$DOTFILES"

    # `close` ends a LIVE workstream (no worktree): it must kill the pi window and
    # refuse to pretend when there is none.
    _close_before="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    _close_out="$(env TMUX="$_pwtsock" fish -N "$_pwtprobe" "$DOTFILES" close "$_pwt_repo" 2>&1)"
    _close_after="$(tmux -S "$_pwtsock" list-windows -t pwttest -F x | wc -l | tr -d ' ')"
    check "pwt: close ends a live workstream's window" \
        bash -c '[[ "$1" -gt "$2" && "$3" == *"closed window"* ]]' \
        _ "$_close_before" "$_close_after" "$_close_out"
    check "pwt: close reports failure where no pi window exists" \
        bash -c '! env TMUX="$1" fish -N "$2" "$3" close /tmp >/dev/null 2>&1' \
        _ "$_pwtsock" "$DOTFILES" "$_pwtprobe"

    # ── reload: restart a live pi in place with a fresh environment ──────────────
    # What proves this worked is what the STUB actually received (it writes
    # RELOAD_PROBE into $PWT_STUB_ENV_OUT), not what pwt printed. The pane id and the
    # @pwt_* markers must survive too, or "the same workstream" is a false claim, and
    # the dead run's @pi_state must not linger on the window.
    _pwt_reload_dir="$(mktemp -d)"
    _pwt_reload_secrets="$(mktemp)"
    tmux -S "$_pwtsock" new-window -t pwttest -n reloadme -c "$_pwt_reload_dir" "sleep 300" >/dev/null 2>&1
    _pwt_rp="$(tmux -S "$_pwtsock" list-panes -t reloadme -F '#{pane_id}')"
    tmux -S "$_pwtsock" select-pane -t "$_pwt_rp" -T 'π - reloadme'
    tmux -S "$_pwtsock" set-window-option -t "$_pwt_rp" @pwt_sid repo-reload
    tmux -S "$_pwtsock" set-window-option -t "$_pwt_rp" @pwt_dir "$_pwt_reload_dir"
    tmux -S "$_pwtsock" set-window-option -t "$_pwt_rp" @pwt_label reloadme
    tmux -S "$_pwtsock" set-window-option -t "$_pwt_rp" @pi_state working
    check "pwt: reload refuses to kill a working agent without --force" \
        bash -c 'env TMUX="$1" fish -N "$2" "$3" reload "$4" >/dev/null 2>&1 && exit 1
            [[ "$(tmux -S "$1" display -p -t "$5" "#{pane_start_command}")" != *repo-reload* ]]' \
        _ "$_pwtsock" "$_pwtprobe" "$DOTFILES" "$_pwt_reload_dir" "$_pwt_rp"
    check "pwt: reload refuses a window pwt did not open" \
        bash -c 'f=$(mktemp -d); trap "rm -rf \"$f\"" EXIT
            tmux -S "$1" new-window -t pwttest -n foreign -c "$f" "sleep 300" >/dev/null 2>&1
            p=$(tmux -S "$1" list-panes -t foreign -F "#{pane_id}")
            tmux -S "$1" select-pane -t "$p" -T "π - foreign"
            out=$(env TMUX="$1" fish -N "$2" "$3" reload "$f" 2>&1) && exit 1
            [[ "$out" == *"records no pwt session id"* ]]' \
        _ "$_pwtsock" "$_pwtprobe" "$DOTFILES"
    : > "$_pwt_envlog"
    printf '%s\n' 'set -gx RELOAD_PROBE fromfile' > "$_pwt_reload_secrets"
    # The caller exports a STALE value on purpose: what must arrive is the file's, or
    # `pwt reload` would re-inject the secret it exists to refresh and report success.
    # The tap is dropped first, so re-attaching it is observable (`#{pane_pipe}`).
    check "pwt: reload replays pi in place with the file's env, not the caller's" \
        bash -c 'tmux -S "$1" pipe-pane -t "$5"
            env TMUX="$1" PWT_SECRETS="$7" RELOAD_PROBE=stale \
                fish -N "$2" "$3" reload --force "$4" >/dev/null 2>&1 || exit 1
            [[ "$(tmux -S "$1" display -p -t "$5" "#{pane_id}")" == "$5" ]] || exit 1
            [[ "$(tmux -S "$1" display -p -t "$5" "#{@pwt_sid}")" == "repo-reload" ]] || exit 1
            [[ -z "$(tmux -S "$1" display -p -t "$5" "#{@pi_state}")" ]] || exit 1
            [[ "$(tmux -S "$1" display -p -t "$5" "#{pane_start_command}")" == *repo-reload* ]] || exit 1
            [[ "$(tmux -S "$1" display -p -t "$5" "#{pane_pipe}")" == "1" ]] || exit 1
            # The stub writes from inside the new process, so poll: asserting on a
            # single immediate read makes this test depend on scheduler luck.
            for i in 1 2 3 4 5 6 7 8 9 10; do
                [[ -n "$(cat "$6")" ]] && break; sleep 0.2
            done
            [[ "$(cat "$6")" == "fromfile" ]]' \
        _ "$_pwtsock" "$_pwtprobe" "$DOTFILES" "$_pwt_reload_dir" "$_pwt_rp" "$_pwt_envlog" \
        "$_pwt_reload_secrets"

    tmux -S "$_pwtsock" kill-server >/dev/null 2>&1
    PATH="$_pwt_path_saved"; export PATH
    unset PWT_STUB_ENV_OUT
    rm -rf "$(dirname "$_pwtsock")" "$(dirname "$_pwt_repo")" "$_pwtprobe" "$_pwt_stub" \
        "$_pwt_envlog" "$_pwt_reload_dir" "$_pwt_reload_secrets"
else
    _skip "pwt: window resolution (behavioural)" "tmux or fish not installed"
fi

# ── pi program-status tap (pwt-osc) ─────────────────────────────────────────
# pi reports working/blocked/done/error over OSC 7501 (superlogical program-status
# protocol). tmux consumes and discards OSC it does not recognise and never answers
# the protocol's support query, so a per-pane `pipe-pane` tap reads the bytes
# before that and mirrors them into @pi_state/@pi_alert. Two traps here cost real
# debugging time and neither is visible by reading the code, so both are asserted:
#   * the report is a RAW OSC that a TUI emits with no newline, and BSD `tr`
#     BLOCK-buffers, so a tr-based splitter delivers nothing until the pane dies;
#   * a FINITE emitter passes even a broken consumer, because everything arrives in
#     the single flush at pane death. The emitter below never exits.
_PWT_OSC="$DOTFILES/base/tmux/bin/pwt-osc"
check "pwt-osc: consumer exists in base/tmux/bin" test -f "$_PWT_OSC"
check "pwt-osc: is executable" test -x "$_PWT_OSC"
check "pwt-osc: shellcheck clean" shellcheck -S warning "$_PWT_OSC"

# The parse half needs no tmux: six states, plus a report carrying no `app` at all
# (accepted) and two that must be dropped — an unknown state, and a nested program
# that adopts the protocol.
_osc_fix="$(mktemp)"
printf '\033]7501;state=idle:app=pi\033\\\n\033]7501;state=working:app=pi\033\\\n\033]7501;state=blocked:kind=auth:app=pi:msg=QUJD\033\\\n\033]7501;state=done:app=pi\033\\\n\033]7501;state=error:app=pi\033\\\n\033]7501;state=clear:app=pi\033\\\n\033]7501;state=bogus:app=pi\033\\\n\033]7501;state=blocked:app=terraform\033\\\n\033]7501;state=working\033\\\n' > "$_osc_fix"
_osc_expect='state=idle app=pi kind=- alert=no
state=working app=pi kind=- alert=no
state=blocked app=pi kind=auth alert=yes
state=done app=pi kind=- alert=yes
state=error app=pi kind=- alert=yes
state=clear app=pi kind=- alert=no
state=working app=- kind=- alert=no'
check "pwt-osc: --parse decides every state and drops impostors" \
    bash -c '[[ "$(env -u TMUX "$1" --parse < "$2")" == "$3" ]]' \
    _ "$_PWT_OSC" "$_osc_fix" "$_osc_expect"
rm -f "$_osc_fix"

# ── push notification (the tap's third job) ─────────────────────────────────
# The flag is ambient and free, but it can only be seen by someone already looking
# at tmux. The push covers the case no flag can: being in another app entirely.
# Same three states, never for progress, never for the window you are looking at,
# and at most one per workstream per cooldown — a live smoke agent settled 7–22
# times on one task, so without the cooldown a single stuck agent is a storm.
check_has "pwt-osc: repeat settles are coalesced by a cooldown" \
    'COOLDOWN_SECONDS=300' "$_PWT_OSC"
# The cooldown lives on the window, so it needs no state directory to clean up and
# dies with the workstream it describes.
check_has "pwt-osc: the cooldown is stamped on the window, not in a temp file" \
    '@pi_notified_at' "$_PWT_OSC"
# A message is program-controlled text on its way to a notifier, so it must arrive
# as DATA: building `display notification "$msg"` is the injection, and osascript
# being handed the text as arguments to `on run argv` is the fix.
check_has "pwt-osc: osascript receives the text as argv, never as script source" \
    'on run argv' "$_PWT_OSC"
check_has "pwt-osc: WSL pushes through a zero-dep WinRT toast" \
    'ToastNotificationManager' "$_PWT_OSC"
check_has "pwt-osc: Linux falls back to notify-send when there is one" \
    'notify-send' "$_PWT_OSC"
# Outside the grid is exactly where the protocol asks for control and bidi
# characters to be disarmed rather than rendered.
check_has "pwt-osc: disarms bidi overrides in a message" \
    'x\{202a\}.*x\{202e\}' "$_PWT_OSC"
check_has "pwt-osc: clamps a message to the length of a banner" \
    'substr\(\$s, 0, 160\)' "$_PWT_OSC"

# Behaviour, not text: drive the REAL consumer with stub tmux over synthetic report
# streams, because window-active suppression, the cooldown and the sanitising are
# decisions. PWT_NOTIFY_CMD — the documented override — becomes the recorder.
if command -v perl >/dev/null 2>&1 && command -v base64 >/dev/null 2>&1; then
    _osc_stub_dir="$(mktemp -d)"; _osc_opt="$_osc_stub_dir/opt"; mkdir -p "$_osc_opt"
    _osc_nlog="$_osc_stub_dir/notify.log"; : > "$_osc_nlog"
    cat > "$_osc_stub_dir/tmux" <<'OSTUB'
#!/bin/bash
# The sliver of tmux the tap touches: format queries, the client list, option writes.
case "$1" in
display-message)
    case "$*" in
    # The default 1 is what a detached server really reports for a session's current
    # window — the trap. A tap that gates on this must fail the checks below.
    *window_active*)     printf '%s\n' "${PWT_STUB_ACTIVE:-1}" ;;
    *@pwt_label*)        printf '%s\n' "${PWT_STUB_LABEL:-}" ;;
    *@pwt_dir*)          printf '%s\n' "${PWT_STUB_DIR:-}" ;;
    *pane_current_path*) printf '%s\n' "${PWT_STUB_CWD:-}" ;;
    *@pwt_notify*)       printf '%s\n' "${PWT_STUB_NOTIFY:-}" ;;
    *@pi_notified_at*)   cat "$PWT_STUB_OPT/@pi_notified_at" 2>/dev/null ;;
    # The client-context query asks for the same format as the pane one, so -c has
    # to be matched before it.
    *-c" "*)             printf '%s\n' "${PWT_STUB_CLIENT_WIN:-}" ;;
    *window_id*)         printf '%s\n' "@99" ;;
    esac ;;
list-clients) printf '%s\n' "${PWT_STUB_CLIENTS:-}" ;;
set-window-option)
    shift 3
    if [ "$1" = "-u" ]; then rm -f "$PWT_STUB_OPT/$2"; else printf '%s\n' "$2" > "$PWT_STUB_OPT/$1"; fi ;;
esac
exit 0
OSTUB
    cat > "$_osc_stub_dir/rec" <<'OREC'
#!/bin/bash
printf '%s|%s\n' "$1" "$2" >> "$PWT_NOTIFY_LOG"
OREC
    chmod +x "$_osc_stub_dir/tmux" "$_osc_stub_dir/rec"
    # <payload> [looking] [label] [cwd] [dir]. `looking` is what the CLIENT list says,
    # not what `window_active` says: 0 nobody attached (which is also what a client on
    # another session's window amounts to), 1 a client whose current window IS this
    # one, 2 a client attached somewhere else. Defaults use - not :- so a case can
    # pass an empty label. PWT_SRC is pinned so the title's $PWT_SRC-relative form is
    # deterministic.
    _osc_raw() {
        local clients='' cwin=''
        case "${2-0}" in
            1) clients=/dev/ttys999; cwin='@99' ;;
            2) clients=/dev/ttys999; cwin='@42' ;;
        esac
        printf '\033]7501;%s\033\\' "$1" \
            | env PATH="$_osc_stub_dir:$PATH" PWT_STUB_OPT="$_osc_opt" \
                  PWT_STUB_CLIENTS="$clients" PWT_STUB_CLIENT_WIN="$cwin" \
                  PWT_STUB_LABEL="${3-audit}" \
                  PWT_STUB_CWD="${4-/src/org/repo/__worktrees/audit}" \
                  PWT_STUB_DIR="${5-}" PWT_SRC=/src \
                  PWT_STUB_NOTIFY="${_osc_mute:-}" \
                  PWT_NOTIFY_CMD="$_osc_stub_dir/rec" PWT_NOTIFY_LOG="$_osc_nlog" "$_PWT_OSC" %99
    }
    # <state> [kind] [msg-b64] [looking] [label] [cwd] [dir]
    _osc_shot() {
        local payload="state=$1:app=pi"
        [[ -n "${2:-}" ]] && payload="$payload:kind=$2"
        [[ -n "${3:-}" ]] && payload="$payload:msg=$3"
        _osc_raw "$payload" "${4-0}" "${5-audit}" "${6-/src/org/repo/__worktrees/audit}" "${7-}"
    }
    _osc_clear() { rm -f "$_osc_opt"/*; : > "$_osc_nlog"; }
    _osc_mute=''   # 0 stands in for `tmux set -g @pwt_notify 0`
    _osc_n() { wc -l < "$_osc_nlog" | tr -d ' '; }

    # `tr -d '\n'` is load-bearing: GNU base64 wraps its output at 76 columns and BSD
    # does not, so a wrapped fixture arrives as SEVERAL lines and the tap — which parses
    # one line per report, as the protocol requires, since a value may not contain a
    # control character and a newline is one — keeps only the first. This is exactly how
    # the clamp check below passed on macOS and failed on CI.
    _osc_head="$(printf 'Waiting for approval:\nrun the tests?' | base64 | tr -d '\n')"
    _osc_clear; _osc_shot blocked auth "$_osc_head" 0 audit
    check "pwt-osc: a blocked report pushes one notification" \
        test "$(_osc_n)" = "1"
    check "pwt-osc: it names the workstream and repeats what pi said" \
        grep -qF 'audit — blocked|Waiting for approval: run the tests?' "$_osc_nlog"
    # A push has exactly one job: send you to the right window. So the title carries
    # the workstream's repo — "audit — blocked" cannot be acted on when two repos
    # hold an audit. @pwt_dir is the workstream's OWN directory, so the title is the
    # panel's label: $PWT_SRC-relative when that applies, repo basename otherwise.
    _osc_clear
    _osc_shot blocked auth "$_osc_head" 0 audit '' /src/org/repo/__worktrees/audit /src/org/repo/__worktrees/audit
    check "pwt-osc: a push qualifies the workstream with its repo" \
        grep -qF 'org/repo/audit — blocked|' "$_osc_nlog"
    _osc_clear
    _osc_shot 'done' '' '' 0 audit '' /elsewhere/repo/__worktrees/audit /elsewhere/repo/__worktrees/audit
    check "pwt-osc: a worktree outside \$PWT_SRC falls back to its repo name" \
        grep -qF 'repo/audit — done|' "$_osc_nlog"
    _osc_clear
    _osc_shot 'done' '' '' 0 audit '' /src/org/repo /src/org/repo
    check "pwt-osc: an in-place workstream is named by its checkout" \
        grep -qF 'org/repo/audit — done|' "$_osc_nlog"
    # The stub answers window_active=1, exactly as a detached server does for a
    # session's current window, and no client is attached: the flag must go up anyway,
    # because nothing is looking at it.
    check "pwt-osc: nobody attached means nobody looking, current window included" \
        test "$(cat "$_osc_opt/@pi_alert")" = "1"
    _osc_shot blocked auth "$_osc_head" 0 audit
    check "pwt-osc: a repeat inside the cooldown pushes nothing" \
        test "$(_osc_n)" = "1"
    printf '1\n' > "$_osc_opt/@pi_notified_at"
    _osc_shot 'done' '' '' 0 audit
    check "pwt-osc: an expired cooldown pushes again" \
        test "$(_osc_n)" = "2"
    check "pwt-osc: the push re-stamps the cooldown" \
        bash -c '[[ "$(cat "$1")" -gt 1600000000 ]]' _ "$_osc_opt/@pi_notified_at"
    _osc_clear; _osc_shot error '' '' 1 audit
    check "pwt-osc: no push for the window you are already looking at" \
        test ! -s "$_osc_nlog"
    check "pwt-osc: that report still records the state and clears the flag" \
        bash -c '[[ "$(cat "$1/@pi_state")" = error && -z "$(cat "$1/@pi_alert")" ]]' _ "$_osc_opt"
    # The other half of that decision: a client IS attached, just not here. Suppressing
    # on "a client exists" rather than "a client is on THIS window" would lose every
    # workstream sitting in another session's current window.
    _osc_clear; _osc_shot blocked auth "$_osc_head" 2
    check "pwt-osc: a client attached elsewhere does not suppress the push" \
        test "$(_osc_n)" = "1"
    check "pwt-osc: nor the flag on that window" \
        test "$(cat "$_osc_opt/@pi_alert")" = "1"
    _osc_clear; _osc_shot working '' '' 0 audit
    check "pwt-osc: progress is never a push" test ! -s "$_osc_nlog"
    _osc_clear; _osc_shot idle '' '' 0 audit
    check "pwt-osc: nor is resting" test ! -s "$_osc_nlog"
    _osc_clear; _osc_mute=0; _osc_shot blocked auth "$_osc_head" 0 audit; _osc_mute=''
    check "pwt-osc: a muted push does not fire" test ! -s "$_osc_nlog"
    check "pwt-osc: muting the push does not mute the flag" \
        test "$(cat "$_osc_opt/@pi_alert")" = "1"
    check "pwt-osc: a muted push leaves no cooldown stamp behind" \
        test ! -e "$_osc_opt/@pi_notified_at"
    _osc_clear; _osc_shot blocked '' '' 0 '' /src/org/repo/__worktrees/del-1119
    check "pwt-osc: an unlabelled session is named by its directory instead" \
        grep -qF 'del-1119 — blocked|pi is waiting on you' "$_osc_nlog"
    _osc_clear; _osc_shot blocked auth '' 0 audit
    check "pwt-osc: a login block with no message still says what it wants" \
        grep -qF 'audit — blocked|sign-in needed' "$_osc_nlog"
    _osc_clear; _osc_raw 'state=done:app=terraform' 0 audit
    check "pwt-osc: another program's report cannot drive a notification" \
        test ! -s "$_osc_nlog"
    _osc_clear; _osc_raw 'state=brokenish:app=pi' 0 audit
    check "pwt-osc: an unknown state notifies nothing" test ! -s "$_osc_nlog"
    _osc_clear; _osc_shot blocked '' '' 0 audit; _osc_raw 'state=clear:app=pi' 0 audit
    check "pwt-osc: clear drops the cooldown too, so the next run can push" \
        test ! -e "$_osc_opt/@pi_notified_at"
    _osc_clear
    _osc_long="$(printf 'x%.0s' $(seq 1 300))"
    _osc_shot blocked custom "$(printf 'need\001a %s decision %s' $'\342\200\256' "$_osc_long" | base64 | tr -d '\n')" 0 audit
    check "pwt-osc: a long message is clamped to a banner" \
        bash -c 'body=${1#*|}; [[ ${#body} -eq 160 ]]' _ "$(tail -1 "$_osc_nlog")"
    check "pwt-osc: control characters and bidi overrides are disarmed" \
        bash -c 'body=${1#*|}; [[ "$body" == "need a decision"* ]]' _ "$(tail -1 "$_osc_nlog")"
    rm -rf "$_osc_stub_dir"
else
    _skip "pwt-osc: push decisions (behavioural)" "perl or base64 not installed"
fi

if command -v tmux >/dev/null 2>&1 && command -v perl >/dev/null 2>&1; then
    _osc_dir="$(mktemp -d)"; _osc_sock="$_osc_dir/sock"
    cat > "$_osc_dir/emit.sh" <<'EMIT'
#!/bin/sh
# Emits ONLY blocked. An alternating emitter makes the alert assertion below a coin
# flip, because a working report legitimately clears the alert — that working clears
# it is asserted by the --parse fixture instead, where the policy is deterministic.
while :; do printf '\033]7501;state=blocked:kind=auth:app=pi\033\\'; sleep 0.25; done
EMIT
    cat > "$_osc_dir/rec" <<'REC'
#!/bin/bash
printf '%s|%s\n' "$1" "$2" >> "$PWT_NOTIFY_LOG"
REC
    chmod +x "$_osc_dir/emit.sh" "$_osc_dir/rec"
    tmux -S "$_osc_sock" -f /dev/null new-session -d -s osctest -c "$_osc_dir" "sleep 300"
    # The decay hooks, taken as they ship (tmux.conf's own text is asserted above
    # instead; this server deliberately loads no file, because loading the real one
    # would run its run-shell against the DEFAULT socket).
    tmux -S "$_osc_sock" set-hook -g pane-focus-in 'set-window-option -u @pi_alert'
    tmux -S "$_osc_sock" set-hook -g after-select-window 'set-window-option -u @pi_alert'
    tmux -S "$_osc_sock" set-hook -g client-focus-in 'set-window-option -u @pi_alert'
    # The emitter shares the FIRST window (index 0) while a distractor takes index
    # 1, so a strftime-mangled `-t 1` is visible to the assertion instead of landing
    # invisibly on the emitter's own window.
    tmux -S "$_osc_sock" split-window -t osctest:0 -c "$_osc_dir" "$_osc_dir/emit.sh"
    tmux -S "$_osc_sock" new-window -t osctest -n distractor -c "$_osc_dir" "sleep 300"
    _osc_pane="$(tmux -S "$_osc_sock" list-panes -t osctest:0 -F '#{pane_id}' | tail -1)"
    _osc_dist="$(tmux -S "$_osc_sock" list-windows -t osctest -F '#{window_index}:#{window_id}' \
        | awk -F: '$1==1{print $2}')"
    tmux -S "$_osc_sock" select-window -t osctest:0
    # #{pane_id}, never the literal id: this string is a strftime template first.
    # The notifier is passed in this command's own environment on purpose: a
    # pipe-pane job does NOT see `set-environment -g`, it inherits the pane's
    # captured environment (see GOTCHAS).
    tmux -S "$_osc_sock" pipe-pane -t "$_osc_pane" \
        "exec env TMUX=$_osc_sock PWT_NOTIFY_CMD=$_osc_dir/rec PWT_NOTIFY_LOG=$_osc_dir/notify.log $_PWT_OSC #{pane_id}"
    _osc_state=''
    for _i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        _osc_state="$(tmux -S "$_osc_sock" display-message -p -t "$_osc_pane" '#{@pi_state}')"
        [ "$_osc_state" = "blocked" ] && break
        sleep 0.5
    done
    check "pwt-osc: a live report reaches @pi_state while the pane lives" \
        test "$_osc_state" = "blocked"
    check "pwt-osc: nothing leaks onto another window (the pane-id trap)" \
        test -z "$(tmux -S "$_osc_sock" display-message -p -t "$_osc_dist" '#{@pi_state}')"
    # No client is attached to this private server, and the emitter's window IS the
    # session's current one — precisely where `#{window_active}` reports 1, and so
    # precisely where the old test suppressed flag and push alike. Nothing is looking
    # at it, so the flag has to go up anyway.
    _osc_alert=''
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        _osc_alert="$(tmux -S "$_osc_sock" display-message -p -t "$_osc_pane" '#{@pi_alert}')"
        [ "$_osc_alert" = "1" ] && break
        sleep 0.5
    done
    check "pwt-osc: a detached server still flags its session's current window" \
        test "$_osc_alert" = "1"
    # The push rides that same report through the same real pipe: the first blocked
    # emit pushes (no client is attached, so nobody is looking) and the rest are
    # coalesced by the cooldown — a stream of them yields exactly one.
    #
    # Wait for the log before asserting. The tap sets @pi_alert and THEN spawns the
    # notifier, so a flag observed above can be a beat ahead of the `rec` write: the
    # assertion is "exactly one push", not "one push within the flag's own write".
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        [ -s "$_osc_dir/notify.log" ] && break
        sleep 0.3
    done
    # Settle one more second before counting: the emitter fires every 0.25 s, so this
    # is the window in which a BROKEN cooldown would produce a second push. Without
    # it the count samples the moment the first line appears and can never see one.
    sleep 1
    check "pwt-osc: a live stream of reports pushes exactly once" \
        test "$(wc -l < "$_osc_dir/notify.log" 2>/dev/null | tr -d ' ')" = "1"
    check "pwt-osc: the live push names the state it is about" \
        bash -c 'grep -q " — blocked" "$1"' _ "$_osc_dir/notify.log"
    # Moving the session to another window must not decay a flag nobody has looked at:
    # the hook clears the window that was SELECTED, not every window.
    tmux -S "$_osc_sock" select-window -t distractor; sleep 0.5
    _osc_alert="$(tmux -S "$_osc_sock" display-message -p -t "$_osc_pane" '#{@pi_alert}')"
    check "pwt-osc: the flag survives the session moving to another window" \
        test "$_osc_alert" = "1"
    # The decay hook, tested deterministically instead of against a live emitter: a
    # window with no emitter behind it, flagged, then SELECTED. The hook clears the
    # window that was selected and leaves the state behind it.
    _osc_decay="$(tmux -S "$_osc_sock" new-window -dP -F '#{window_id}' -t osctest \
        -n decay -c "$_osc_dir" 'sleep 300')"
    tmux -S "$_osc_sock" set-window-option -t "$_osc_decay" @pi_alert 1
    tmux -S "$_osc_sock" set-window-option -t "$_osc_decay" @pi_state 'done'
    tmux -S "$_osc_sock" select-window -t "$_osc_decay"; sleep 0.5
    check "pwt-osc: looking at a flagged window decays the flag and keeps the state" \
        bash -c '[[ -z "$(tmux -S "$1" display-message -p -t "$2" "#{@pi_alert}")" && \
                  "$(tmux -S "$1" display-message -p -t "$2" "#{@pi_state}")" = done ]]' \
        _ "$_osc_sock" "$_osc_decay"
    # And in the emitter's window the flag comes BACK after the hook clears it: nobody
    # is attached, so the next report raises it again. Under the old `window_active`
    # gate this could never happen — that window was treated as being looked at.
    tmux -S "$_osc_sock" select-window -t osctest:0; sleep 0.6
    check "pwt-osc: the flag is raised again while nothing is attached" \
        bash -c '[[ "$(tmux -S "$1" display-message -p -t "$2" "#{@pi_alert}")" = 1 ]]' \
        _ "$_osc_sock" "$_osc_pane"
    tmux -S "$_osc_sock" kill-server >/dev/null 2>&1
    rm -rf "$_osc_dir"
else
    _skip "pwt-osc: tap behaviour (behavioural)" "tmux or perl not installed"
fi

# ── pi session prune policy ──────────────────────────────────────────────────
# Sessions are KEPT, not scheduled away: the transcripts are the only source for
# session review and for the /usage dashboard, which reads this directory.
# pi-prune-sessions therefore stays a manual tool, and the tombstone below keeps
# an automatic scheduler from creeping back (one existed briefly on 2026-10-11).
section "pi session prune policy"

_PI_PRUNE_SCHED="$DOTFILES/base/fish/.config/fish/conf.d/pi-prune.fish"
check "pi-prune: no conf.d auto-prune (sessions are kept, not deleted)" \
    test ! -e "$_PI_PRUNE_SCHED"
check_has "pi-prune-sessions: documents that it is manual-only" \
    'MANUAL ONLY' "$_PI_PRUNE"

# ── pi installation method ───────────────────────────────────────────────────
# pi is deliberately NOT mise-managed (AGENTS.md: self-updating apps with their
# own managed install own themselves).  Three facts force it: mise only
# re-resolves `latest` when `mise upgrade` runs (it sat on 0.80.10 from July
# while upstream reached 1.2.0), its install dir precedes ~/.local/bin on PATH
# and so shadows the managed entrypoint, and pi's updater classifies installs by
# path — an aqua-extracted binary is "unknown", so `pi update --self` refuses
# with "cannot self-update this installation".  The managed install
# (install.sh, PI_MANAGED_INSTALL_ROOT) is the only layout where it works.
# Host-local assertions are skipped on machines without pi (CI runners).
section "Pi installation method"

check_not "mise: pi is NOT mise-managed (managed install owns it)" \
    '^pi[[:space:]]*=' "$MISE_CFG"

check_has "bootstrap: ensure_pi defined" \
    '^ensure_pi\(\)' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: ensure_pi runs the pi managed installer" \
    'pi\.dev/install\.sh' "$DOTFILES/bootstrap.sh"

check "bootstrap: ensure_pi is called after ensure_mise (mise node provides npm)" \
    bash -c "grep -A1 -- 'ensure_mise\$' '$DOTFILES/bootstrap.sh' | grep -q 'ensure_pi'"

# The shim and install-dir handling moved into the shared helper when the two
# ensure_* functions were merged, so these assert the generic form; the per-tool
# wiring is asserted by the delegation guards in the upgrade-routine section.
check_has "bootstrap: _ensure_self_managed drops the stale mise shim" \
    'mise/shims/\$name' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: _ensure_self_managed prunes the stale mise install dir" \
    'mise/installs/\$name' "$DOTFILES/bootstrap.sh"

if command -v pi >/dev/null 2>&1; then
    check "pi: resolves to the managed entrypoint, not a mise install or shim" \
        bash -c 'case "$(command -v pi)" in "$HOME/.local/share/mise/"*) exit 1;; *) exit 0;; esac'

    check "pi: no stale mise install directory" \
        test ! -d "$HOME/.local/share/mise/installs/pi"

    # mise leaves the shim behind after `mise uninstall pi`; ensure_pi removes
    # it.  While present it keeps mise first on PATH for pi and breaks
    # install.sh's first-on-PATH check.  -L as well as -e: a dangling shim
    # (mise binary gone) is still stale state, and -e would follow the link.
    check "pi: no stale mise shim (dangling links count)" \
        bash -c 'p="$HOME/.local/share/mise/shims/pi"; [[ ! -e "$p" && ! -L "$p" ]]'

    check "pi: managed install marker present" \
        test -f "$HOME/.pi/agent/install/managed-install.json"

    check "pi: launcher exports PI_MANAGED_INSTALL_ROOT (self-update path)" \
        grep -q 'PI_MANAGED_INSTALL_ROOT' "$HOME/.pi/agent/bin/pi"
else
    _skip "pi: managed install (PATH resolution, marker, launcher)" \
        "pi not installed on this machine"
fi

# ── Claude Code installation method ──────────────────────────────────────────
# Same ownership rule as pi, for the same reasons (AGENTS.md): claude is NOT
# mise-managed.  A mise/aqua copy (2.1.294) shadowed the native install (2.1.193)
# and could never self-update — Claude Code's updater only touches the native
# layout under ~/.local/share/claude/versions.  ensure_claude() runs the upstream
# installer (checksum-verified) and keeps an existing install on latest via
# `claude update`.  Host-local assertions are skipped on machines without claude
# (CI runners).
section "Claude Code installation method"

check_not "mise: claude is NOT mise-managed (native install owns it)" \
    '^claude[[:space:]]*=' "$MISE_CFG"

check_has "bootstrap: ensure_claude defined" \
    '^ensure_claude\(\)' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: ensure_claude runs the native installer" \
    'claude\.ai/install\.sh' "$DOTFILES/bootstrap.sh"

check "bootstrap: ensure_claude is called after ensure_mise (curl + jq available)" \
    bash -c "grep -A2 -- 'ensure_mise\$' '$DOTFILES/bootstrap.sh' | grep -q 'ensure_claude'"

if command -v claude >/dev/null 2>&1; then
    check "claude: resolves to the native install, not a mise copy" \
        bash -c 'case "$(command -v claude)" in "$HOME/.local/share/mise/"*) exit 1;; *) exit 0;; esac'

    check "claude: no stale mise install directory" \
        test ! -d "$HOME/.local/share/mise/installs/claude"

    # Symmetric with ensure_claude's -L || -e guard: a dangling shim is stale too.
    check "claude: no stale mise shim (dangling links count)" \
        bash -c 'p="$HOME/.local/share/mise/shims/claude"; [[ ! -e "$p" && ! -L "$p" ]]'

    # The native layout is what the updater keys off, so assert it directly
    # rather than trusting the version string.
    check "claude: resolves inside the native versions tree" \
        bash -c 'case "$(realpath "$(command -v claude)")" in "$HOME/.local/share/claude/"*) exit 0;; *) exit 1;; esac'
else
    _skip "claude: native install (PATH resolution, layout, shim, mise leftovers)" \
        "claude not installed on this machine"
fi

# ── Agent upgrade routine (deliberate) ───────────────────────────────────────
# pi and claude install themselves (sections above), but bootstrap must NOT
# upgrade them.  An upgrade swaps the harness under the prompts this repo ships,
# so it has to be paired with the pi-smoke / PROMPT-EVAL pass
# that only a human can judge.  `agents-update` is that deliberate pairing; the
# tombstones below keep a forced update from creeping back into bootstrap.
# They match invocation lines only — prose about updating starts with '#', so a
# comment saying "upgrades live in agents-update" cannot trip them.
section "Agent upgrade routine (deliberate)"

check_not "bootstrap: no forced pi upgrade (deliberate, not a bootstrap step)" \
    '^[[:space:]]*pi (update|upgrade)' "$DOTFILES/bootstrap.sh"

check_not "bootstrap: no forced claude upgrade (deliberate, not a bootstrap step)" \
    '^[[:space:]]*claude (update|upgrade)' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: shared _ensure_self_managed helper defined" \
    '^_ensure_self_managed\(\)' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: ensure_pi delegates to the shared helper" \
    '_ensure_self_managed pi' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: ensure_claude delegates to the shared helper" \
    '_ensure_self_managed claude' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: the skip message names the upgrade path" \
    'upgrade: agents-update' "$DOTFILES/bootstrap.sh"

_AGENTS_UPDATE="$DOTFILES/base/fish/.config/fish/functions/agents-update.fish"
check "agents-update: function exists in base/fish" \
    test -f "$_AGENTS_UPDATE"
if command -v fish >/dev/null 2>&1; then
    check "agents-update: parses (fish -n)" \
        fish -n "$_AGENTS_UPDATE"
fi
check_has "agents-update: updates pi via its own updater" \
    'pi update --self' "$_AGENTS_UPDATE"
check_has "agents-update: updates Claude Code via its own updater" \
    'claude update' "$_AGENTS_UPDATE"
check_not "agents-update: no vendored pin left to compare" \
    '@ pi ' "$_AGENTS_UPDATE"
check_has "agents-update: names the smoke eval a harness move owes" \
    'pi-smoke' "$_AGENTS_UPDATE"

# The extension is not a copy any more: it resolves pi's own example from the
# active release at load time, which is what dropped the re-vendor ritual.  Both
# halves are asserted — resolves the release, and carries no vendored header.
check_has "pi: subagent extension loads from the active pi release" \
    'current-version' "$DOTFILES/base/pi/.pi/agent/extensions/subagent/index.ts"
check_not "pi: subagent extension is not a vendored copy" \
    'Vendored from pi examples' "$DOTFILES/base/pi/.pi/agent/extensions/subagent/index.ts"

# The counters are only readable next to what produced them, and a baseline that
# cannot name its prompt or harness is what made the 2026-10-09 numbers useless.
check_has "pi-smoke: stamps harness provenance into the outdir" \
    'provenance\.txt' "$DOTFILES/pi-smoke.sh"

check_has "pi-smoke: stamps the prompt identity (words + hash)" \
    'prompt       APPEND_SYSTEM' "$DOTFILES/pi-smoke.sh"

# The fish .gitignore is an allowlist (functions/* is ignored unless negated), so
# a new own-file silently drops out of the repo without this — which is exactly
# what happened to agents-update.fish on the first attempt at this commit.
check_has "agents-update: not gitignored (fish allowlist negation present)" \
    '!functions/agents-update\.fish' "$DOTFILES/base/fish/.config/fish/.gitignore"

check_has "conf.d/mise.fish: not gitignored (fish allowlist negation present)" \
    '^!conf\.d/mise\.fish' "$DOTFILES/base/fish/.config/fish/.gitignore"

# Generic form of the same trap, so the next new own-file cannot slip through.
# Covers completions/ as well as conf.d/ and functions/: the .gitignore is an
# ALLOWLIST, so a new own-file in any of them is silently ignored and never
# committed. This test was on functions/ only until conf.d/mise.fish fell straight
# into it — same trap, one directory over — and completions/ was the third: its
# pattern was `completions/` (a DIRECTORY, which git cannot re-include from) rather
# than `completions/*`, so the negation below it did nothing.
check "fish: no own function, conf.d or completion file is untracked or ignored (allowlist trap)" \
    bash -c "cd '$DOTFILES' && test -z \"\$(git ls-files --others --exclude-standard base/fish/.config/fish/functions/ base/fish/.config/fish/conf.d/ base/fish/.config/fish/completions/; git ls-files --others --ignored --exclude-standard base/fish/.config/fish/functions/ base/fish/.config/fish/conf.d/ base/fish/.config/fish/completions/)\""

# fish autoloads a function ONLY from a file named after it. A helper defined
# inside another function's file is therefore an unknown command until that file
# happens to be sourced — how work-login called three helpers that existed only
# after work-status had run in the same shell, silently probing nothing. Any
# `__helper` a functions/ file calls must be defined in that file, or have its own
# <helper>.fish somewhere in a functions dir.
_autoload_bad="$(python3 - "$DOTFILES" <<'PY'
import os, re, subprocess, sys
root = sys.argv[1]
tracked = [f for f in subprocess.run(['git', '-C', root, 'ls-files', '*/functions/*.fish'],
           capture_output=True, text=True).stdout.split('\n') if f]

def strip_comments(t):
    out, q, c = [], None, False
    for ch in t:
        if c:
            if ch == '\n':
                c = False; out.append(ch)
        elif q:
            if ch == q: q = None
            out.append(ch)
        elif ch in '\'"': q = ch; out.append(ch)
        elif ch == '#': c = True
        else: out.append(ch)
    return ''.join(out)

body = {f: strip_comments(open(os.path.join(root, f), errors='ignore').read()) for f in tracked}
defined = {f: set(re.findall(r'^[ \t]*function[ \t]+([^ \t\r\n;]+)', b, re.M)) for f, b in body.items()}
where = {n: f for f, ns in defined.items() for n in ns}
autoloadable = {os.path.basename(f)[:-5] for f in tracked}
for f, b in body.items():
    for name in sorted(set(re.findall(r'(?<![\w./-])(__[A-Za-z0-9_]+)(?![\w./-])', b))):
        if name in defined[f] or name in autoloadable:
            continue
        owner = where.get(name)
        print(f"{f}: calls '{name}'" + (f" — defined only in {owner}, so it is missing until that file is sourced" if owner else " — defined nowhere in a functions dir"))
PY
)"
[[ -n "$_autoload_bad" ]] && printf '      %s\n' "$_autoload_bad"
check "fish: every cross-file __helper is autoloadable (one function per file)" \
    test -z "$_autoload_bad"

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
