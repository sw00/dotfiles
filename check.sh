#!/usr/bin/env bash
# =============================================================================
# check.sh — dotfiles test suite
#
# Usage:  ./check.sh              fast: static/pin/parsability checks only (~8s)
#         CHECK_FULL=1 ./check.sh  full: + behavioural fixtures, node suites, lint
#         CI=1 ./check.sh          full too (CI sets CI, so pushes gate on everything)
# Exit:   0 = all tests passed, 1 = one or more failures
#
# The default run DEFERS the behavioural half — tmux/git/fish fixtures, the
# `node --test` suites, shellcheck over every script, host probes — and says how
# many checks it deferred in the summary (`○ N behavioural checks deferred`).
# Rationale, in the owner's words: this is a dotfiles repo of config and glue, not a
# complex application, so a fast feedback loop is worth less coverage. Everything
# static — every pin, every parsability check, every "the file says X" assertion —
# still runs in both modes. A deferred check never prints ✓ and is never counted as
# passed; only a CHECK_FULL/CI run's pass count means anything.
#
# Measured on mbpm3 (2026-11): ~48s full, ~8s fast, ~765 checks. Do not trust a
# number you have not measured — run it in the foreground, or poll for "── Results".
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
# A fixture that rewrites $HOME also breaks every MISE SHIM on PATH: mise re-derives
# its config/state/trust from HOME, decides the user config is untrusted, and exits
# non-zero — or silently falls back to a system binary. Measured 2026-11-05: from this
# repo's cwd `tmux list-panes` and `python3 os.path.realpath` returned NOTHING under a
# throwaway HOME, failing two assertions for reasons unrelated to the code under test
# (and, from another cwd, passing — a cwd-dependence that made it read as a flake).
# Resolve the real tool dirs ONCE, with the real HOME, and let those fixtures put them
# ahead of the shims. Empty where mise is absent (CI), which changes nothing there.
_MISE_REAL_BINS=""
if command -v mise >/dev/null 2>&1; then
    # Resolved from $DOTFILES, not the invoking cwd: mise answers per directory.
    _MISE_REAL_BINS="$(cd "$DOTFILES" && mise bin-paths 2>/dev/null | tr '\n' ':' | sed 's/:$//')"
fi
# The value must never be interpolated bare: an empty `$_MISE_REAL_BINS` would make
# `PATH=":$PATH"`, whose leading empty element is the CWD — a fake `python3` in the
# working directory would then answer for the real one. CI installs no mise, so that
# is the NORMAL case there, not a corner.
# Exported because the fixtures below are CHILD processes (`bash -c '…'`), where a
# plain shell variable reads as empty and puts the shims back in front — which is how
# this fix first looked like it had not worked.
export _MISE_REAL_BINS
PASS=0; FAIL=0; SKIP=0; DEFERRED=0
FAILED=()

# ── Fast by default, full on demand ────────────────────────────────────────
# This repo is config and glue, so the owner's steer is a sub-12s feedback loop at
# the cost of coverage: the BEHAVIOURAL half of the suite (tmux/git/fish fixtures,
# node --test suites, shellcheck, host probes) is DEFERRED unless CHECK_FULL=1 or
# CI is set. Every static/pin/parsability assertion still runs in both modes, so
# the default run still proves the config is what it says it is; what it stops
# proving is that the helpers BEHAVE. CI sets CI, so pushes gate on everything.
_full() { [[ ${CHECK_FULL:-0} == 1 || -n ${CI:-} ]]; }
# Deferred checks are their own bucket: they are neither passed nor skipped-with-
# needs, and they never print a ✓. N is the number of runner calls in the block.
_defer() { DEFERRED=$((DEFERRED + ${1:-1})); }

# Opt-in timing. `CHECK_PROFILE=1 bash check.sh` collects each check's wall time
# and prints the slowest at the end, so "the suite is slow" turns into a ranked
# list instead of a guess. Off by default: the guard below is one string compare.
PROFILE_ROWS=()
_profile() {  # <name> <start-epochrealtime>
    [[ ${CHECK_PROFILE:-0} == 1 ]] || return 0
    # [.,] on purpose: EPOCHREALTIME uses the LOCALE's decimal point, so a
    # comma-locale host stripped nothing and every row failed `value too great for
    # base` — the profiler printed nothing at all on such a host.
    local now=${EPOCHREALTIME//[.,]/} t0=${2//[.,]/}
    PROFILE_ROWS+=("$(( now - t0 ))"$'\t'"${SECTION}"$'\t'"$1")
}
_profile_report() {
    [[ ${CHECK_PROFILE:-0} == 1 && ${#PROFILE_ROWS[@]} -gt 0 ]] || return 0
    printf '\n%bSlowest checks:%b\n' "$(_c "$BLD")" "$(_c "$RST")"
    printf '%s\n' "${PROFILE_ROWS[@]}" | sort -t$'\t' -k1,1 -gr | head -10 |
        while IFS=$'\t' read -r us name; do
            printf '  %6d ms  %s\n' "$(( us / 1000 ))" "$name"
        done
    printf '\n%bWall time by section:%b\n' "$(_c "$BLD")" "$(_c "$RST")"
    printf '%s\n' "${PROFILE_ROWS[@]}" | awk -F'\t' '{ s[$2] += $1; n[$2]++ }
        END { for (k in s) printf "%8d ms  %4d checks  %s\n", s[k]/1000, n[k], k }' | sort -gr | head -12
}
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

# Colour is resolved ONCE into variables: `$(_c …)` forks a subshell per call, and
# these three primitives run on every check (~800 forks a run, ~1ms each, for a
# string that never changes). `_c` stays for the handful of non-hot call sites.
if [[ -t 1 ]]; then
    C_GRN=$GRN; C_RED=$RED; C_YLW=$YLW; C_RST=$RST
else
    C_GRN=; C_RED=; C_YLW=; C_RST=
fi

_ok()   { printf '  %b✓%b %s\n' "$C_GRN" "$C_RST" "$1"; PASS=$((PASS+1)); }
_fail() { printf '  %b✗%b %s\n' "$C_RED" "$C_RST" "$1"; FAIL=$((FAIL+1)); FAILED+=("[$SECTION] $1"); }
_skip() { printf '  %b○%b %s  (needs: %s)\n' "$C_YLW" "$C_RST" "$1" "$2"; SKIP=$((SKIP+1)); }

# Run a test: pass if the command exits 0, fail otherwise.
# Both stdout and stderr from the command are suppressed.
check() {
    local name="$1"; shift
    local _t0=""
    [[ ${CHECK_PROFILE:-0} == 1 ]] && _t0=${EPOCHREALTIME//[.,]/}
    if "$@" >/dev/null 2>&1; then _ok "$name"; else _fail "$name"; fi
    _profile "$name" "$_t0"
}

# One BEHAVIOURAL check: runs in full mode (CHECK_FULL=1 / CI), counted as deferred
# otherwise and never printed. Used where the fixture around it is cheap and only
# the check itself is expensive; a block whose SETUP is expensive is gated whole.
check_full() {
    if _full; then check "$@"; else _defer 1; fi
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
# ...and a sandboxed-HOME fixture must run REAL tools, never mise shims (see
# _MISE_REAL_BINS above): under a throwaway HOME a shim exits non-zero or silently
# substitutes a system binary, which cost two false failures on 2026-11-05.
check_has "check.sh: the real tool dirs are resolved once (mise bin-paths)" \
    'mise bin-paths' "$DOTFILES/check.sh"
# The pins require the ${VAR:+…} form specifically: `${VAR:-}` with an empty value
# yields `PATH=":…"`, whose leading empty element is the CWD — a planted `sh` would
# then answer for the real one. (A pin on the bare variable would accept that.)
check_has "check.sh: the pi-settings migration fixture guards an empty value" \
    'env HOME="\$d" PATH="\$\{_MISE_REAL_BINS:\+' "$DOTFILES/check.sh"
# Behavioural and HOST-INDEPENDENT, because CI is exactly where the value is EMPTY
# (no mise, so no shims): build the production expression with an empty value, plant
# a fake `sh` in the cwd, and require the real one to answer. A `${VAR:-…}` form or a
# bare interpolation fails here; so does a value that never reaches the expression.
check "check.sh: an empty real-tool value never puts the CWD on PATH" bash -c '
    d=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
    printf "#!/bin/sh\necho FAKE\n" >"$d/sh"; chmod +x "$d/sh"
    bins=
    got=$(cd "$d" && PATH="${bins:+$bins:}/bin:/usr/bin" command -v sh)
    case "$got" in /bin/sh|/usr/bin/sh) ;; *) exit 1 ;; esac'
# The two fixtures above are the mechanism guard: if the bin list ever comes back
# empty, shimmy or unexported, they fail again by name — a dedicated "is the value
# usable" assertion would only make the diagnosis read faster.

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

# Linting is the one EXPENSIVE static check (a real analyser, ~100ms+ per script).
# The per-script `bash -n` run above already proves parsability in BOTH modes, so the
# lint pass is deferred to full mode rather than deleted: it catches semantics, not
# syntax, and a push still runs it.
if command -v shellcheck >/dev/null 2>&1; then
    if _full; then
        for s in "${ALL_SCRIPTS[@]}"; do
            rel="${s#"$DOTFILES/"}"
            check "shellcheck: $rel" shellcheck -S warning "$s"
        done
    else
        _defer "${#ALL_SCRIPTS[@]}"
    fi
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
check_stow "base: git nvim ssh fish tmux alacritty mise pi sesh tokentelemetry claude worktrunk paseo nono" \
    "$DOTFILES/base" git nvim ssh fish tmux alacritty mise pi sesh claude worktrunk paseo nono
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
# A runtime notice flag is per-machine state, not config: the dotfile sets
# provider.plan so the bridge's first-run notice never fires, and
# askClaudeDeprecationShown is written when the extension shows a deprecation notice
# (one was committed this way on 2026-10-21 and reverted). Committing either makes the
# next host inherit "already seen" for a notice it never saw, and tests nothing — the
# keys that DO belong here are asserted above. Which stowed files can be dirtied, and
# why only a stowed file can be, is in docs/GOTCHAS.md ("stow lifecycle").
# NOT "git show -- :path": with the -- it is a PATHSPEC and git prints the commit that
# last touched the file, so a staged flag passed the check. `git show :path` is the
# staged blob, and a path absent from the index must FAIL (rc=128) rather than pass
# vacuously through a silenced error.
check "pi: no runtime notice flag is staged in claude-bridge.json" \
    bash -c 'blob=$(git -C "$1" show ":base/pi/.pi/agent/claude-bridge.json") || exit 1
             ! grep -qE "(startupNoticeShown|askClaudeDeprecationShown)" <<<"$blob"' \
    _ "$DOTFILES"

# ── Linux stack: base → os/linux ───
section "Stow integrity — Linux stack  [GREEN]"

stow_begin
stow_layer "$DOTFILES/base" git nvim ssh fish tmux alacritty mise pi sesh worktrunk
check_stow "os/linux: alacritty" \
    "$DOTFILES/os/linux" alacritty
stow_end

# ── macOS stack: base → os/macos → hosts/mbpm3 ───
section "Stow integrity — macOS stack  [GREEN]"

stow_begin
stow_layer "$DOTFILES/base" git nvim ssh fish tmux pi sesh worktrunk
check_stow "os/macos: brew gnupg" \
    "$DOTFILES/os/macos" brew gnupg

stow_layer "$DOTFILES/os/macos" brew gnupg
check_stow "hosts/mbpm3: alacritty brew fish key_remap mise aerospace paseo" \
    "$DOTFILES/hosts/mbpm3" alacritty brew fish key_remap mise aerospace paseo
stow_end

# ── WSL stack: base → os/linux → os/wsl ───
# os/wsl/windows/ holds content for the Windows side (pushed by up.sh, not stowed).
# Stow packages are listed explicitly in bootstrap.sh (git, gnupg, alacritty).
section "Stow integrity — WSL stack  [GREEN]"

stow_begin
stow_layer "$DOTFILES/base" git nvim ssh fish tmux alacritty mise pi sesh worktrunk
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
# the week a completion and a bin script landed in already-stowed packages.
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

# fish's own embedded scripts execute `true`/`false` BY NAME — `if $flag`, where
# $flag holds the string "false" — so a host-local definition of either inverts fish's
# internals: `~/.config/fish/functions/false.fish` (return 0) broke theme application
# and blanked every fish_color_* (docs/GOTCHAS.md → fish). Only those two names are
# checked; wrapping a builtin such as `cd` is a legitimate thing for a user to do.
# Machine-only: CI has no live ~/.config/fish.
if [[ -z "${CI:-}" ]] && command -v fish >/dev/null 2>&1; then
    _shadowed=
    for _fn in true false; do
        for _dir in "$HOME/.config/fish/functions" "$HOME/.config/fish/conf.d"; do
            if [[ -e "$_dir/$_fn.fish" ]]; then
                _shadowed="$_shadowed $_dir/$_fn.fish"
            fi
        done
        if [[ -f "$HOME/.config/fish/config.fish" ]] \
            && grep -qEs "^(function|alias)[[:space:]]+$_fn([[:space:]]|$)" \
                "$HOME/.config/fish/config.fish"; then
            _shadowed="$_shadowed ~/.config/fish/config.fish($_fn)"
        fi
    done
    check "fish: no host-local override of true/false${_shadowed:+ — found:$_shadowed}" \
        test -z "$_shadowed"
else
    _skip "fish: no host-local override of true/false" "CI environment or fish not installed"
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

# PiG reaches pi's state dir only through this one shell-local export, so it is
# asserted as CONTENT rather than "a file exists": any other value (0, true, the
# empty string) leaves PiG on its own ~/.pig/agent — different settings, an unseeded
# trust store, and none of the extensions this repo ships — with nothing reporting
# an error. Deliberately in conf.d/ and never in ~/.pi/agent/settings.json: settings
# travel with the shared dir, so a value there would follow the rollback binary too.
_PIG_CONFD="$DOTFILES/base/fish/.config/fish/conf.d/pig.fish"
check "pig.fish: exactly one line, set -gx PIG_USE_PI_DIRS 1" \
    bash -c 'test "$(grep -cE "^set -gx PIG_USE_PI_DIRS 1$" "$1")" = 1 &&
             test "$(grep -cE "PIG_USE_PI_DIRS" "$1")" = 1' _ "$_PIG_CONFD"
# conf.d/* is an ALLOWLIST in .gitignore, so the file is invisible (and never
# committed) unless it is re-included — the trap that cost a conf.d/mise.fish.
check_has "gitignore: conf.d/pig.fish is re-included (conf.d/* is an allowlist)" \
    '^!base/fish/\.config/fish/conf\.d/pig\.fish$' "$DOTFILES/.gitignore"


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

# The non-comment assignment lines of one tool's table. A key written after a
# table header belongs to THAT table in TOML, so this is the whole entry — which
# is what lets the assertions below tell "python sets a postinstall" from "some
# postinstall sits somewhere in the file".
_table_block() {
    awk -v hdr="$1" '/^\[/ { tbl = ($0 == hdr); next }
         tbl && !/^[[:space:]]*(#|$)/' "$MISE_CFG"
}

check_has "mise: neovim is managed by mise (not snap/apt)" \
    'neovim' "$MISE_CFG"

check_has "mise: fzf is managed by mise" \
    'fzf' "$MISE_CFG"

check_has "mise: node runtime is declared" \
    'node' "$MISE_CFG"

# The declaration SITE is what is asserted, not the string: a broken pin or an
# entry moved under another tool's table header still greps. python is a table (not
# `python = "3.12.13"`) because it carries a postinstall, so its keys are matched
# inside that table — a `postinstall` floating under some other tool is not one.
check_has "mise: python runtime is declared as a tool table" \
    '^\[tools\.python\]$' "$MISE_CFG"
check_has "mise: python is pinned to an exact x.y.z" \
    '^version[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"$' <(_table_block '[tools.python]')
# That postinstall is the only thing installing the interpreter's shared package
# list (libtmux, for tmux-window-name), so it must not vanish silently.
check_has "mise: python carries the postinstall that installs its package list" \
    '^postinstall[[:space:]]*=[[:space:]]*"python -m pip install -r ~/\.config/mise/default-python-packages"$' \
    <(_table_block '[tools.python]')

# mise deprecates `{python,node}.default_packages_file` (warned from 2026.11,
# removed in 2027.11.0): python carries a tool-level postinstall, node needs no
# package list (every global npm tool is an npm: entry). Tombstoned in the global
# config AND in every host layer (~/.mise.toml is a live mise config too).
# `grep -q` must answer "no match" (1) and nothing else: 0 is the setting coming
# back, 2 an unreadable file that would otherwise read as clean.
_mise_configs=("$MISE_CFG")
for _f in "$DOTFILES"/hosts/*/mise/.mise.toml; do
    [[ -e "$_f" ]] && _mise_configs+=("$_f")
done
check "mise: the deprecated default_packages_file settings never come back" \
    bash -c 'for f; do grep -q "default_packages_file" "$f"; [ $? -eq 1 ] || exit 1; done' \
    _ "${_mise_configs[@]}"

check_has "mise: tmux is managed by mise (not apt/brew)" \
    '^tmux ' "$MISE_CFG"

check_has "mise: sesh managed by mise (ubi backend)" \
    'ubi:joshmedeski/sesh' "$MISE_CFG"

check_has "mise: lf managed by mise (ubi backend)" \
    'ubi:gokcehan/lf' "$MISE_CFG"

# ── PiG (the harness this repo provisions) ────────────────────────────────
# PiG is the ONE harness mise owns, and unlike every neighbour it is pinned to an
# exact version: an upgrade swaps the harness under the prompts this repo ships, so
# the pin may only move in a reviewable commit paired with the pi-smoke /
# PROMPT-EVAL pass (`agents-update` runs `mise upgrade --bump` and the diff IS the
# review). `latest` here would move it silently on the next `mise upgrade`, which is
# why the pin is matched as x.y.z specifically rather than as "a version string".
_pig_table_block() {
    _table_block '[tools."ubi:MichaelKinsy/PiG"]'
}
check_has "mise: PiG is declared as a ubi table entry" \
    '^\[tools\."ubi:MichaelKinsy/PiG"\]$' "$MISE_CFG"
# The entry's own assignment lines. A key written after a table header belongs to
# THAT table in TOML, so this block is the whole entry — which is what makes the
# assertions below precise (exe present, and nothing else nested in by accident).
check_has "mise: the PiG pin is an exact x.y.z" \
    '^version[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"$' <(_pig_table_block)
check_not "mise: the PiG pin never floats on latest" \
    'latest' <(_pig_table_block)
# `exe` is load-bearing, not cosmetic: ubi looks for an archive member matching the
# repo name and PiG's release ships the binary as `pig`, so without it `mise install`
# fails with "could not find any files matching [PiG*]".
check_has "mise: the PiG entry names exe = pig (ubi cannot guess the archive member)" \
    '^exe[[:space:]]*=[[:space:]]*"pig"$' <(_pig_table_block)
check "mise: the PiG entry holds exactly version + exe (no key nested in it)" \
    test "$(_pig_table_block | wc -l | tr -d ' ')" = 2
check_not "mise: the PiG pin never reappears in the floating key form" \
    '"ubi:MichaelKinsy/PiG"[[:space:]]*=[[:space:]]*"latest"' "$MISE_CFG"

# ── nono (§8-admitted kernel FS boundary) ───────────────────────────────────
# Admitted 2026-11-21 with one condition: the telemetry opt-outs stay declared
# (docs/AGENT-SAFETY.md §8, §3 probe H). `ubi:` is deprecated in mise 2027.1.0, so
# the registry's `github:` backend owns it. An exact pin is load-bearing: a version
# move under the boundary is a safety change, not a tool refresh.
_nono_table_block() {
    _table_block '[tools."github:nolabs-ai/nono"]'
}
check_has "mise: nono declared as a github table entry" \
    '^\[tools\."github:nolabs-ai/nono"\]$' "$MISE_CFG"
check_has "mise: the nono pin is an exact x.y.z" \
    '^version[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"$' <(_nono_table_block)
check_not "mise: the nono pin never floats on latest" \
    'latest' <(_nono_table_block)
check_not "mise: ubi:nolabs-ai/nono is tombstoned (deprecated backend)" \
    'ubi:nolabs-ai/nono' "$MISE_CFG"

_NCFG="$DOTFILES/base/nono/.config/nono/config.toml"
_NPROF="$DOTFILES/base/nono/.config/nono/profiles/agent.json"
check "nono: telemetry opt-out config exists" test -f "$_NCFG"
check_has "nono: update checks and pack hints opt-out declared (check = false)" \
    '^check[[:space:]]*=[[:space:]]*false$' "$_NCFG"
check_not "nono: update check never re-enabled in the tracked config" \
    '^check[[:space:]]*=[[:space:]]*true' "$_NCFG"
check "nono: profile exists" test -f "$_NPROF"
check_has "nono: profile extends default" \
    '"extends"[[:space:]]*:[[:space:]]*"default"' "$_NPROF"
check "nono: profile denies the MAIN personal secret store path in filesystem.deny" \
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if any("dotfiles/secrets" in p for p in d.get("filesystem",{}).get("deny",[])) else 1)' "$_NPROF"
check_has "bootstrap: stow_dir includes nono" \
    'stow_dir.*DOTFILES/base.*nono' "$DOTFILES/bootstrap.sh"
if command -v nono >/dev/null 2>&1; then
    # --strict pins the canonical schema (no legacy keys). NONO_NO_UPDATE_CHECK=1
    # keeps the suite's own probe from writing update-check.json on a host whose
    # base/nono package has not been stowed yet — the check must not cause the
    # telemetry it guards.
    check "nono: the tracked profile validates (strict)" \
        env NONO_NO_UPDATE_CHECK=1 nono profile validate "$_NPROF" --strict
    check "nono: sandbox support is live on this host" \
        env NONO_NO_UPDATE_CHECK=1 nono setup --check-only
else
    _skip "nono: the tracked profile validates" \
        "nono is not on PATH (mise install; pin is github:nolabs-ai/nono)"
    _skip "nono: sandbox support is live on this host" \
        "nono is not on PATH (mise install; pin is github:nolabs-ai/nono)"
fi

# gitleaks backs the publish guard (class c: a credential riding out inside a
# `gh pr create --body`). The guard fails CLOSED when it cannot find a scanner, so
# this declaration is what keeps every publish and web call from blocking — and the
# DECLARATION SITE is what is asserted, not the string: a tool written under another
# tool's table header is an unknown key on that tool, not a declared tool, so mise
# would never install it while `grep` still found the line.
check "mise: gitleaks is declared in [tools] (not nested in another tool's table)" \
    bash -c 'awk "/^\[/ { table = \$0; next }
        table == \"[tools]\" && /^\"aqua:gitleaks\/gitleaks\"[ \t]*=/ { found = 1 }
        END { exit(found ? 0 : 1) }" "$1"' _ "$MISE_CFG"

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

# Notion CLI: no mise registry entry and no GitHub releases (binaries come from
# ntn.dev), so the npm package is the only mise-ownable channel. Pin the spec so
# a rewrite to the self-managing `curl ntn.dev | bash` install can't slip in —
# that copy updates itself and mise would silently keep serving the stale one.
check_has "mbpm3 mise: notion cli declared via npm backend" \
    '"npm:ntn"' "$DOTFILES/hosts/mbpm3/mise/.mise.toml"

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
# /usr/bin/make still wins and only `gmake` is reachable from it. The consumer is
# the FLEET, not this repo: the IaC repo's Makefile uses $(abspath) and two work
# repos use .ONESHELL. Both are 4.x-only and both degrade SILENTLY on 3.81, which
# is why this is asserted rather than left to whoever notices a broken build.
# Repo names stay out of this public tree — the workbench records which ones.
# (The workbench itself no longer needs gmake; its Makefile was verified on 3.81.)
check_has "Brewfile-base: make present (provides gmake; macOS make is 3.81)" \
    'brew "make"' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "Brewfile-base: obsidian present" \
    'obsidian' "$DOTFILES/os/macos/brew/.Brewfile-base"

# Flameshot is a tap cask, not a homebrew/cask one: the canonical cask was
# disabled 2026-09-01 (`because: :fails_gatekeeper_check`), so bootstrap must
# declare the tap, the tap-qualified cask name AND `trusted: true` — Homebrew 7
# refuses to load a cask from an untrusted third-party tap, and trust otherwise
# lives in host-local ~/.homebrew/trust.json, which a fresh machine lacks. The
# quarantine strip is the other half of that gap: a cask install leaves the
# download's xattr on the .app and Gatekeeper kills it on launch (Killed: 9,
# exit 137).
check_has "Brewfile-base: flameshot present (core desktop app, upstream tap)" \
    'cask "flameshot-org-flameshot"' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "Brewfile-base: flameshot cask trusted (third-party tap, no host trust.json)" \
    'cask "flameshot-org-flameshot", trusted: true' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "Brewfile-base: flameshot-org/flameshot tap declared (source of the flameshot cask)" \
    'tap "flameshot-org/flameshot"' "$DOTFILES/os/macos/brew/.Brewfile-base"

# Tombstone: the disabled core cask must not return. It cannot install at all,
# and its Caskroom entry would own — and could later delete — the tap cask's app.
# check_not + an ERE that tolerates quote style and any separator after the name:
# a plain `! grep "cask \"flameshot\""` silently passes on `cask 'flameshot'`.
check_not "Brewfile-base: no homebrew/cask flameshot (disabled; tap cask only)" \
    "^cask[[:space:]]+[\"']flameshot[\"']([[:space:],]|$)" \
    "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "bootstrap.sh: strips the Flameshot quarantine (notarization gap)" \
    'xattr -dr com.apple.quarantine "\$app"' "$DOTFILES/bootstrap.sh"

check "bootstrap.sh: quarantine strip called in the macOS branch (after app trim)" bash -c \
    "grep -A4 '^            migrate_app_trim\$' '$DOTFILES/bootstrap.sh' \
        | grep -q '^            ensure_flameshot_quarantine\$'"

# The rename needs a migration, not just a Brewfile edit: the old cask owns
# /Applications/Flameshot.app, so the new cask cannot install over it and the
# stale entry would later delete the new app.
check_has "bootstrap.sh: old flameshot cask migration defined (2026-11 tap move)" \
    'migrate_flameshot_tap_cask()' "$DOTFILES/bootstrap.sh"

check "bootstrap.sh: flameshot migration runs on macOS before brew bundle" bash -c \
    "grep -B1 '^            ensure_homebrew_bundle\$' '$DOTFILES/bootstrap.sh' \
        | grep -q 'migrate_flameshot_tap_cask'"

# Behavioural, not a grep pin: the migration must actually uninstall the old cask,
# and must not touch brew when it is absent. bootstrap.sh runs main on source, so
# the function is extracted; `brew` is a shell function, so this needs no Homebrew
# and runs on the Linux CI runner too.
_FS_MIG=$(mktemp)
awk '/^migrate_flameshot_tap_cask\(\)/,/^}$/' "$DOTFILES/bootstrap.sh" > "$_FS_MIG"
check_full "bootstrap: flameshot migration uninstalls the old cask only when present" bash -c '
    fn="$1"
    log() { :; }; warn() { :; }
    _calls=""
    brew() {
        case "$1 $2" in
            "list --cask") printf "%s\n" "$FAKE_LIST" ;;
            *) _calls+="$* " ;;
        esac
    }
    . "$fn"
    FAKE_LIST="flameshot
    alacritty"
    migrate_flameshot_tap_cask
    case "$_calls" in
        "uninstall --cask flameshot ") ;;
        *) echo "old-cask branch did not uninstall it: [$_calls]"; exit 1 ;;
    esac
    _calls=""
    FAKE_LIST="flameshot-org-flameshot"
    migrate_flameshot_tap_cask
    [ -z "$_calls" ] || { echo "touched brew with the old cask absent: [$_calls]"; exit 1; }
' _ "$_FS_MIG"
rm -f "$_FS_MIG"

# ZapFast is cask-only on macOS (author tap) and MSI-seeded on Windows:
# microsoft/winget-pkgs has no ZapFast manifest, so it has no winget ID and
# stays out of the PARITY loop below, which asserts one for every core desktop
# cask. The Windows declaration is a comment in winget.txt + the pinned MSI
# block in up.sh — guard both, or the platform parity is only a comment.
#
# The up.sh guards run against the zapfast BLOCK, not the whole file: a bare
# `DisplayName` or `Get-FileHash` anywhere in up.sh would pass even with this
# seed block gutted. Extraction is marker-based — banner comment to the
# `rm -f "$PS_ZAPFAST"` cleanup.
check_has "Brewfile-base: zapfast present (core desktop app, author tap)" \
    'cask "zapfast"' "$DOTFILES/os/macos/brew/.Brewfile-base"

check_has "Brewfile-base: crmne/tap declared (source of the zapfast cask)" \
    'tap "crmne/tap"' "$DOTFILES/os/macos/brew/.Brewfile-base"

_ZAPFAST_PS=$(mktemp)
awk '/^# ── ZapFast \(Windows app/,/^rm -f "\$PS_ZAPFAST"$/' \
    "$DOTFILES/os/wsl/up.sh" > "$_ZAPFAST_PS"

check_has "up.sh: zapfast seeds a pinned MSI (release URL built from the pin)" \
    'zapfast/releases/download/v\$version' "$_ZAPFAST_PS"

check_has "up.sh: zapfast verifies the downloaded MSI against the pin" \
    '\$actual -ne \$sha' "$_ZAPFAST_PS"

# Bumping the pin must move the version AND both arch hashes together; the
# runtime Get-FileHash mismatch is what catches a half-done bump, this only
# catches a hash being dropped. Both values are checked against the release's
# checksums.txt when they change.
check "up.sh: zapfast pins one sha256 per arch (x86_64 + aarch64)" \
    bash -c '[ "$(grep -oE "\b[0-9A-F]{64}\b" "$1" | wc -l | tr -d " ")" -eq 2 ]' \
    _ "$_ZAPFAST_PS"

check_has "up.sh: zapfast stops only a self-updating (>= 0.20.0) install" \
    '0\.20\.0' "$_ZAPFAST_PS"

check_has "up.sh: zapfast treats reboot exit codes as success (3010/1641)" \
    '-notin 0, 3010, 1641' "$_ZAPFAST_PS"

check_has "up.sh: zapfast sentinel matches both app names (FastsApp pre-0.13)" \
    "DisplayName -match 'ZapFast\|FastsApp'" "$_ZAPFAST_PS"

rm -f "$_ZAPFAST_PS"

check_has "winget.txt: zapfast documented as up.sh-seeded (no winget ID)" \
    '^# ZapFast' "$DOTFILES/os/wsl/windows/winget.txt"

check_not "winget.txt: zapfast not listed as a winget ID (no manifest exists)" \
    '^[^#]*[Zz]ap[Ff]ast' "$DOTFILES/os/wsl/windows/winget.txt"

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
_leak_shapes='awsapps[.]com|eks[.]amazonaws[.]com|ar[o]app[.]io|sso_(start_url|account_id)|e[y]J|[$]2[aby][$][0-9]{2}[$]'
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

# ── git-crypt filters that survive a linked worktree ─────────────────────────
section "git-crypt worktree filters  [GREEN]"
# git-crypt's key lives at <git-dir>/git-crypt/keys, and a linked worktree's git
# dir (.git/worktrees/<n>) has none — its own checkout then dies at the smudge
# filter and `git worktree add` exits 128. base/git/bin/git-crypt-filter falls
# back to the main repo's key through commondir, and bootstrap points BOTH filter
# directions at it. Local-only: a locked clone may have no git-crypt driver
# configured at all, and CI never runs the behavioural half.
check "git-crypt: worktree filter shim present and executable" \
    test -x "$DOTFILES/base/git/bin/git-crypt-filter"

# The shim has no *.sh suffix (the syntax pass globs only *.sh/*.bash), so without
# this its only coverage would be the CHECK_FULL behavioural test below.
check "git-crypt: worktree filter shim parses (sh -n)" \
    sh -n "$DOTFILES/base/git/bin/git-crypt-filter"

check_has "bootstrap: wires the worktree-safe git-crypt filters" \
    'shim="\$DOTFILES/base/git/bin/git-crypt-filter"' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: wires both filter directions" \
    'filter\.git-crypt\.clean' "$DOTFILES/bootstrap.sh"

check_has "bootstrap: runs the wiring unconditionally (repairs an unlocked clone)" \
    '^    _ensure_worktree_git_crypt_filters$' "$DOTFILES/bootstrap.sh"

if head -c 10 "$DOTFILES/secrets/leak-patterns" 2>/dev/null | grep -aq GITCRYPT; then
    _skip "git-crypt: both filters point at the worktree shim" \
        "locked clone (CI has no git-crypt key)"
    _skip "git-crypt: a fresh linked worktree checks out clean" \
        "locked clone (CI has no git-crypt key)"
else
    # Pinned exactly, not "contains git-crypt": a bare `git-crypt unlock` writes
    # the plain "git-crypt" values back over these and silently re-breaks every
    # worktree add, so the failure has to name the drift.
    _gc_shim="$DOTFILES/base/git/bin/git-crypt-filter"
    check "git-crypt: smudge filter is the worktree shim" \
        test "$(git -C "$DOTFILES" config --local --get filter.git-crypt.smudge)" = "\"$_gc_shim\" smudge"
    check "git-crypt: clean filter is the worktree shim" \
        test "$(git -C "$DOTFILES" config --local --get filter.git-crypt.clean)" = "\"$_gc_shim\" clean"

    # The real regression test: a tree this clone has never checked out. Both
    # directions are exercised, because the status must come back EMPTY — a
    # smudge-only fix leaves it dirty ("clean filter failed") instead.
    # --detach so a failed cleanup cannot leak a branch into the next run; under
    # mktemp, never __worktrees/ (that exclude rule is per-clone, wt-exclude writes it,
    # and `git clean -X -ff` deletes worktrees parked there). Cleanup is a trap,
    # not a happy path: check.sh never aborts, so a leak would be silent.
    check_full "git-crypt: a fresh linked worktree checks out clean" bash -c '
        set -u
        repo=$1
        tmp=$(mktemp -d) || exit 1
        wt=$tmp/wt
        cleanup() {
            # No `worktree prune` here: that prunes EVERY stale entry in the real
            # repo, so a check could delete admin state for a worktree on an
            # unmounted drive. This test removes its own entry explicitly, and a
            # rolled-back `add` leaves none.
            git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1
            rm -rf "$tmp"
        }
        trap cleanup EXIT
        git -C "$repo" worktree add --detach "$wt" HEAD >/dev/null 2>&1 || exit 1
        out=$(git -C "$wt" status --porcelain 2>&1) || exit 1
        [ -z "$out" ]
    ' bash "$DOTFILES"
fi

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

check_has "winget.txt: Paseo present (parity with cask paseo)" \
    'Paseo.Paseo' "$DOTFILES/os/wsl/windows/winget.txt"

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

# Set 1: cross-platform desktop apps — each base macOS cask has a winget twin,
# except the exclusions below. Aerospace (macOS only) and komorebi/whkd/Git.Git
# (Windows only) are platform-only by design. ZapFast is cross-platform but has
# no winget manifest: its Windows side is seeded by up.sh's pinned MSI block and
# guarded above, so no parity row is possible until a manifest exists.
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
flameshot-org-flameshot|Flameshot.Flameshot
telegram|Telegram.TelegramDesktop
firefox@developer-edition|Mozilla.Firefox.DeveloperEdition
paseo|Paseo.Paseo
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

check "brew: nothing in migrate_app_trim's list is also declared in a Brewfile" \
    python3 -c '
import re, sys
boot = open(sys.argv[1]).read()
m = re.search(r"local trimmed=\((.*?)\)", boot, re.S)
if not m:
    sys.stderr.write("cannot find the trimmed array in bootstrap.sh\n")
    sys.exit(1)
trimmed = set(m.group(1).split())
declared = set()
for path in sys.argv[2:]:
    try:
        text = open(path).read()
    except OSError:
        continue                      # host Brewfile absent (CI / another host)
    for line in text.splitlines():
        mm = re.match(r"\s*(?:cask|brew) \"([^\"]+)\"", line)
        if mm:
            declared.add(mm.group(1).lower())
both = sorted(trimmed & declared)
if both:
    sys.stderr.write("trimmed AND declared: " + ", ".join(both) + chr(10))
    sys.exit(1)
' "$DOTFILES/bootstrap.sh" "$BREW_BASE" "$BREW_HOST"

# Behavior, not just the list: the migration must actually uninstall the app its
# declaration was dropped for, or a superseded client lingers unpatched.
check_has "bootstrap.sh: removes the superseded WhatsApp app (mas 310633997)" \
    'mas uninstall 310633997' "$DOTFILES/bootstrap.sh"
# ...and the guard around it must match `mas list`, which INDENTS every line. The
# first version was line-anchored and silently never ran. Pin the exact expression
# (literal grep: it is shell source, not a regex) so a revert fails here.
check "bootstrap.sh: the mas guard tolerates the indent mas list prints" \
    grep -qF '(^|[[:space:]])310633997([[:space:]]|$)' "$DOTFILES/bootstrap.sh"

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
        '$DOTFILES/base/pi/.pi/agent/settings.desired.json'"

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
# infra-safety + /check mode correctly classify mutations vs. reads whichever
# shell tool the session actually has: lib/mutation-guard.ts exports ONE
# SHELL_TOOLS constant ("bash" + "hypa_shell") and both gates read it, so the
# gate is neither hypa-only nor bash-only.
#
# A green `node --test` summary is not evidence: a suite whose cases all SKIP, or a
# runner that counted nothing, still exits 0 while passing nothing. So the pass
# count itself is pinned, and `# tests`/`# fail`/`# skipped` have to agree with it —
# a case that silently stopped running cannot be laundered through a green summary.
# Re-pin a count only when the test file gained cases deliberately.
_TS_PIN_MUTATION_GUARD=36
_TS_PIN_PUBLISH_SCAN=33
_TS_PIN_PUBLISH_GUARD=17
# L2's file-tool half: the secret-path predicate and the tool list it gates.
_TS_PIN_SECRET_PATHS=14
# Dispatch-only: the extension is driven by a fake `pi`, so no case sends a real push.
_TS_PIN_SETTLE_NOTIFY=10
# /check's read-only allowlist: the decision logic lives in lib/ so it is drivable
# without the harness (modes/index.ts imports typebox, which lib/ cannot resolve).
_TS_PIN_CHECK_MODE=52
# The fallback WIRING (event ordering, provenance, the down-provider latch) — the
# pure helpers were tested while the handlers that own the bugs were not.
_TS_PIN_MODEL_SWITCH=3
_ts_suite_count() {  # <test file in lib/> <expected pass count>
    local file="$1" want="$2" out pass tests failed skipped
    out=$(cd "$DOTFILES/base/pi/.pi/agent/extensions" \
        && node --experimental-strip-types --test "lib/$file" 2>&1)
    pass=$(printf '%s\n' "$out" | sed -n 's/^# pass \([0-9][0-9]*\)$/\1/p')
    tests=$(printf '%s\n' "$out" | sed -n 's/^# tests \([0-9][0-9]*\)$/\1/p')
    failed=$(printf '%s\n' "$out" | sed -n 's/^# fail \([0-9][0-9]*\)$/\1/p')
    skipped=$(printf '%s\n' "$out" | sed -n 's/^# skipped \([0-9][0-9]*\)$/\1/p')
    [[ "$pass" == "$want" && "$tests" == "$want" && "$failed" == 0 && "$skipped" == 0 ]]
}
if [[ "$_CAN_STRIP_TS" -eq 1 ]]; then
    if _full; then
        # The provider fallback is TEXT-driven because a pre-stream HTTP error never
        # produces after_provider_response: measured on opencode-go's subscription
        # 403, which the status allowlist cannot see. Pure decision logic -> tested.
        check "pi: provider-fallback tests pass" \
            bash -c "cd '$DOTFILES/base/pi/.pi/agent/extensions' && node --experimental-strip-types --test lib/provider-fallback.test.ts"
    else
        _defer 1
    fi
    check_has "pi: provider fallback resolves the error text at turn_end" \
        'pi.on\("turn_end"' "$DOTFILES/base/pi/.pi/agent/extensions/model-switch.ts"
    # pi classifies some of these errors as non-retryable (its list names OpenCode
    # Go's usage-limit errors), so the hop alone can leave the turn dead: this is
    # the one-continuation guard that makes the first turn survive either way.
    check_has "pi: a hop forces one continuation when pi will not retry" \
        'agent_before_settle' "$DOTFILES/base/pi/.pi/agent/extensions/model-switch.ts"
    check_has "pi: the provider hop can never loop on itself" \
        'entry.to === provider' "$DOTFILES/base/pi/.pi/agent/extensions/lib/provider-fallback.ts"
# Both recoveries must ask the same provenance question: an explicit `--model` on
# this invocation is the user's choice, not a leftover twin to undo. The rate-limit
# handler checked only in-process state, so a fresh process re-probed anyway.
check "pi: both fallback recoveries honour an explicit --model" \
    bash -c "[[ \$(grep -c 'shouldReprobePrimary({' '$DOTFILES/base/pi/.pi/agent/extensions/model-switch.ts') -eq 2 ]]"
    if _full; then
        check "pi: mutation-guard suite passes $_TS_PIN_MUTATION_GUARD/$_TS_PIN_MUTATION_GUARD (count pinned)" \
            _ts_suite_count mutation-guard.test.ts "$_TS_PIN_MUTATION_GUARD"
        # L4's pure core: the publish decision (which calls publish, and whether the
        # outgoing text carries a credential) is hermetic and separately counted, so a
        # guard that stopped scanning or a suite that stopped running is visible.
        check "pi: publish-scan suite passes $_TS_PIN_PUBLISH_SCAN/$_TS_PIN_PUBLISH_SCAN (count pinned)" \
            _ts_suite_count publish-scan.test.ts "$_TS_PIN_PUBLISH_SCAN"
        # Notification dispatch is driven through a FAKE pi object, so this suite proves
        # the event choice, the suppression and the fail-safe without sending anything.
        check "pi: settle-notify suite passes $_TS_PIN_SETTLE_NOTIFY/$_TS_PIN_SETTLE_NOTIFY (count pinned)" \
            _ts_suite_count settle-notify.test.ts "$_TS_PIN_SETTLE_NOTIFY"
        # L4's WIRING (handler, scanner process, fail-closed branches) is separately
        # counted: the pure-core suite passing is not evidence that the hook blocks.
        check "pi: publish-guard wiring suite passes $_TS_PIN_PUBLISH_GUARD/$_TS_PIN_PUBLISH_GUARD (count pinned)" \
            _ts_suite_count publish-guard.test.ts "$_TS_PIN_PUBLISH_GUARD"
        # /check is the mode that must not write. Its allowlist is decision logic
        # (fd/uniq/yq/tree removed, git branch/remote/reflog list-only, no env-prefix
        # strip, curl without -o), so a case per escape is what keeps it honest.
        check "pi: check-mode allowlist suite passes $_TS_PIN_CHECK_MODE/$_TS_PIN_CHECK_MODE (count pinned)" \
            _ts_suite_count check-mode.test.ts "$_TS_PIN_CHECK_MODE"
        # The two session_start recoveries must ask the same provenance question and
        # a hop that failed must not latch its provider down: both were wrong and
        # no test covered the wiring that owned them.
        check "pi: model-switch wiring suite passes $_TS_PIN_MODEL_SWITCH/$_TS_PIN_MODEL_SWITCH (count pinned)" \
            _ts_suite_count model-switch.test.ts "$_TS_PIN_MODEL_SWITCH"
    else
        _defer 6
    fi
else
    _skip "pi: mutation-guard suite passes $_TS_PIN_MUTATION_GUARD/$_TS_PIN_MUTATION_GUARD (count pinned)" \
        "node build lacks --experimental-strip-types TS support (need v23+ or TS-compiled build)"
    _skip "pi: publish-scan suite passes $_TS_PIN_PUBLISH_SCAN/$_TS_PIN_PUBLISH_SCAN (count pinned)" \
        "node build lacks --experimental-strip-types TS support (need v23+ or TS-compiled build)"
    # Same gap, same reason: without this line the wiring suite vanished silently
    # on every host whose node cannot strip types.
    _skip "pi: publish-guard wiring suite passes $_TS_PIN_PUBLISH_GUARD/$_TS_PIN_PUBLISH_GUARD (count pinned)" \
        "node build lacks --experimental-strip-types TS support (need v23+ or TS-compiled build)"
    _skip "pi: check-mode allowlist suite passes $_TS_PIN_CHECK_MODE/$_TS_PIN_CHECK_MODE (count pinned)" \
        "node build lacks --experimental-strip-types TS support (need v23+ or TS-compiled build)"
    _skip "pi: model-switch wiring suite passes $_TS_PIN_MODEL_SWITCH/$_TS_PIN_MODEL_SWITCH (count pinned)" \
        "node build lacks --experimental-strip-types TS support (need v23+ or TS-compiled build)"
fi

# edit-guardian appends a whitespace-/Unicode-escaped diagnostic when a built-in
# edit fails to match (blank-line count, leading indent, unfolded non-ASCII).
# The pure core lives in lib/ so it is testable and never auto-loaded as an
# extension (root-level *.ts would be); assert the tests + the load split hold.
if [[ "$_CAN_STRIP_TS" -eq 1 ]]; then
    check_full "pi: edit-guardian diagnostic tests pass" \
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
    check_full "pi: no-powershell platform-tools tests pass" \
        bash -c "cd '$DOTFILES/base/pi/.pi/agent/extensions' && node --experimental-strip-types --test lib/platform-tools.test.ts"
else
    _skip "pi: no-powershell platform-tools tests pass" \
        "node build lacks --experimental-strip-types TS support (need v23+ or TS-compiled build)"
fi

check "pi: edit-guardian test lives in lib/ (never auto-loaded as an extension)" \
    bash -c "! ls '$DOTFILES/base/pi/.pi/agent/extensions'/*.test.ts >/dev/null 2>&1"

# A path-less recursive search (pi's grep/find with no path — i.e. how a repo is
# usually searched) walks the worktree, and `secrets/*` is git-tracked, so no ignore
# rule excluded it: measured, a bare `grep GITHUB_TOKEN` from the repo root printed
# the token. ripgrep and fd honour `.ignore`, so one line there closes the shape
# without the L2 gate having to deny every bare `grep` (which would make the repo
# unsearchable). Deliberately NOT `.gitignore`: these files stay tracked and
# addable, and an explicit path is still searched (ignore rules skip only the walk).
check "pi: a path-less search cannot walk into the credential store" \
    bash -c "grep -qx 'secrets/' '$DOTFILES/.ignore'"

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

with open('$DOTFILES/base/pi/.pi/agent/settings.desired.json') as f:
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
# The search route is brave → exa, and it is only alive while NO scalar
# `provider`/`searchProvider` key exists: pi-web-access gives a scalar precedence
# over `searchRouting`, and the curator's provider picker writes that scalar back
# through the stowed symlink into this tracked file — dirtying the repo AND
# silently disabling the route. So assert the ABSENCE, not just the route, or
# that footgun ships green. The key half is a policy pin (docs/AGENT-SAFETY.md §5):
# each key is one `!` getter call naming the store variable, because this repo is
# public and a value must never reach this file. Pinned EXACTLY rather than "either
# form": a revert to a `$NAME` env reference would otherwise ship green and re-break
# every session that never ran `creds`. The base URLs are pinned absent because they
# decide where the key is sent, and a `!` getter would carry it there as happily. The
# env channel (`BRAVE_BASE_URL`/`EXA_BASE_URL`, utils.ts resolveApiBaseUrl) outranks
# config and is out of scope here: it belongs to the launching environment, which no
# agent sets for its own parent.
check "pi: web-search routes brave -> exa with no scalar provider" \
    bash -c "python3 -c \"
import json, sys
ws = json.load(open('$DOTFILES/base/pi/.pi/web-search.json'))
scalars = [k for k in ('provider', 'searchProvider') if k in ws]
if scalars:
    sys.stderr.write('scalar %r present: searchRouting is dead config\\n' % (scalars,))
    sys.exit(1)
route = ws.get('searchRouting') or {}
if route.get('providers') != ['brave', 'exa']:
    sys.stderr.write('searchRouting.providers must be [brave, exa]: %r\\n' % (route.get('providers'),))
    sys.exit(1)
need = {'quota', 'transient', 'network', 'invalid-response', 'empty'}
missing = need - set(route.get('fallbackOn') or [])
if missing:
    sys.stderr.write('searchRouting.fallbackOn missing %r\\n' % (sorted(missing),))
    sys.exit(1)
allowed = set((ws.get('webSearch') or {}).get('allowedProviders') or [])
if not {'brave', 'exa'} <= allowed:
    sys.stderr.write('webSearch.allowedProviders must allow brave and exa: %r\\n' % (sorted(allowed),))
    sys.exit(1)
want = {'braveApiKey': '!~/bin/web-search-key BRAVE_SEARCH_API_KEY',
        'exaApiKey': '!~/bin/web-search-key EXA_SEARCH_API_KEY'}
for field, accepted in want.items():
    if str(ws.get(field, '')) != accepted:
        sys.stderr.write('%s must be exactly %r (a value never reaches this file)\n' % (field, accepted))
        sys.exit(1)
for field in ('braveBaseUrl', 'exaBaseUrl'):
    if field in ws:
        sys.stderr.write('%s would redirect the key; it must be absent\n' % (field,))
        sys.exit(1)
\""

# Removed 2026-11-21: measured on pi-web-access 0.48.0, its SSRF guard rejects a LAN
# `firecrawlBaseUrl` without `ssrf.allowRanges`. Re-entry needs a host-level override for
# web-search.json (one stowed symlink — GOTCHAS) plus that range, not a base edit.
check_not "pi: no firecrawl* fetch shim in web-search.json (Eyes shim, removed 2026-11-21)" \
    '[Ff]irecrawl' "$DOTFILES/base/pi/.pi/web-search.json"

# The getter that pin names: one key per call, for pi-web-access' `!command` credential
# form (docs/AGENT-SAFETY.md §5). Static half here, behaviour on a sandboxed HOME below.
_WSEARCH_KEY="$DOTFILES/base/pi/bin/web-search-key"
check "web-search-key: is executable (pi-web-access execs it directly)" test -x "$_WSEARCH_KEY"
check "web-search-key: parses (sh -n)" sh -n "$_WSEARCH_KEY"
check_full "web-search-key: shellcheck clean as POSIX sh" shellcheck -S warning -s sh "$_WSEARCH_KEY"

# Behaviour, on a sandboxed HOME: this is a credential path, so the refusal matters more
# than the happy path. Every value here is fake and invented; nothing reads the real
# store. The third variable IS in the fixture store and off the allowlist — a fixture
# with only allowlisted names proves nothing about the allowlist.
_wsk_d=$(mktemp -d) || {
    echo "mktemp failed; the fixture writes fake stores under it" >&2
    exit 1
}
_wsk_h="$_wsk_d/home"
mkdir -p "$_wsk_h/dotfiles/secrets" "$_wsk_d/locked/dotfiles/secrets" "$_wsk_d/sparse/dotfiles/secrets"
printf '%s\n' 'set -gx BRAVE_SEARCH_API_KEY fake-brave' 'set -gx EXA_SEARCH_API_KEY fake-exa' \
    'set -gx OTHER_TOKEN fake-other' >"$_wsk_h/dotfiles/secrets/env.fish"
printf '%s\n' 'set -gx BRAVE_SEARCH_API_KEY fake-brave' >"$_wsk_d/sparse/dotfiles/secrets/env.fish"
# git-crypt ciphertext is READABLE, so a lock is only detectable by its magic — the same
# one the L0 probe above relies on. This asserts the OUTCOME (nothing is handed out), not
# which guard fired: measured 2026-11-21, fish refuses a NUL-bearing file outright, so
# disabling the header test still ends in the empty-result guard. The header test is
# defence in depth (an interpreter never parses those bytes) and is deliberately not
# asserted as the mechanism; the empty-result guard gets its own case just below.
printf '\0GITCRYPT\0\n' >"$_wsk_d/locked/dotfiles/secrets/env.fish"
printf 'set -gx BRAVE_SEARCH_API_KEY fake-leaked\n' >>"$_wsk_d/locked/dotfiles/secrets/env.fish"
check_full "web-search-key: a store variable off the allowlist is refused" \
    bash -c 'HOME="$1" "$2" OTHER_TOKEN >/dev/null 2>&1; [ $? -eq 2 ]' _ "$_wsk_h" "$_WSEARCH_KEY"
# The header refusal names itself on stderr before fish is ever consulted, so this case
# runs ungated — and it is the only assertion that can fail if the header guard is
# deleted (fish refuses NUL of its own accord, so the outcome-only case below stays
# green without it).
check_full "web-search-key: a locked store says so, before fish is consulted" \
    bash -c 'HOME="$1" "$2" BRAVE_SEARCH_API_KEY 2>&1 >/dev/null | grep -q "git-crypt locked"' \
    _ "$_wsk_d/locked" "$_WSEARCH_KEY"
# Everything below has to reach fish, so on a host without it the getter fails for the
# wrong reason and an `[ -z "$out" ] && [ "$st" -ne 0 ]` shape would pass regardless of
# the guard under test. Gated, not merely skipped into a shared `if`.
if command -v fish >/dev/null 2>&1; then
    check_full "web-search-key: a git-crypt-locked store hands out nothing" \
        bash -c 'out=$(HOME="$1" "$2" BRAVE_SEARCH_API_KEY 2>/dev/null); st=$?; [ -z "$out" ] && [ "$st" -ne 0 ]' \
        _ "$_wsk_d/locked" "$_WSEARCH_KEY"
    # Allowlisted, but the store defines no such value — the guard a locked store falls
    # through to, so it is asserted directly. Delete the empty-result check and this goes
    # green while handing out an empty key: the failure becomes "search gets nothing".
    check_full "web-search-key: an allowlisted name the store does not define is refused" \
        bash -c 'out=$(HOME="$1" "$2" EXA_SEARCH_API_KEY 2>/dev/null); st=$?; [ -z "$out" ] && [ "$st" -ne 0 ]' \
        _ "$_wsk_d/sparse" "$_WSEARCH_KEY"
    check_full "web-search-key: an allowlisted name prints exactly its value" \
        bash -c '[ "$(HOME="$1" "$2" BRAVE_SEARCH_API_KEY)" = fake-brave ]' _ "$_wsk_h" "$_WSEARCH_KEY"
    # The daemon's PATH need not carry Homebrew, and the bug this fixes lives on the
    # daemon path: the absolute-path fallback is the mechanism, so it is worth asserting.
    # Not the same case in CI — there fish is on /usr/bin, already on the test's PATH.
    check_full "web-search-key: finds fish with a PATH that has no Homebrew" \
        bash -c '[ "$(env -i HOME="$1" PATH=/usr/bin:/bin "$2" EXA_SEARCH_API_KEY)" = fake-exa ]' \
        _ "$_wsk_h" "$_WSEARCH_KEY"
else
    # Fast mode already counted these four as deferred (`check_full` -> `_defer`); printing
    # them as skipped-with-needs would double-count and misreport why.
    if _full; then
        _skip "web-search-key: a git-crypt-locked store hands out nothing" "fish is not installed"
        _skip "web-search-key: an allowlisted name the store does not define is refused" "fish is not installed"
        _skip "web-search-key: an allowlisted name prints exactly its value" "fish is not installed"
        _skip "web-search-key: finds fish with a PATH that has no Homebrew" "fish is not installed"
    else
        _defer 4
    fi
fi
rm -rf "$_wsk_d"

# The route is a privacy statement before it is a configuration, and the claim
# that matters is the NEGATIVE one: Exa's ZDR is an Enterprise-only feature
# (exa.ai/docs/admin/security/zero-data-retention) and its privacy policy says
# query data trains models, so a row implying peer-level ZDR would be a lie the
# README tells about this host. Python, not check_has: the row is
# pipe-delimited markdown, and ERE would read every `|` as alternation — a
# pattern that matches anything proves nothing.
check "pi: README ZDR table states Exa has no ZDR (Enterprise-only)" \
    bash -c "python3 -c \"
import sys
rows = [l for l in open('$DOTFILES/base/pi/README.md') if 'Exa (keyed API)' in l]
if len(rows) != 1:
    sys.stderr.write('expected exactly one Exa ZDR row, found %d\\n' % (len(rows),))
    sys.exit(1)
cells = [c.strip() for c in rows[0].strip().strip('|').split('|')]
if len(cells) != 4:
    sys.stderr.write('Exa row must have 4 cells: %r\\n' % (cells,))
    sys.exit(1)
training, retention = cells[2], cells[3]
if 'Enterprise' not in retention or 'Zero' in retention:
    sys.stderr.write('Exa RETENTION cell must state Enterprise-only, never Zero: %r\\n' % (retention,))
    sys.exit(1)
if training.lower().startswith('no'):
    sys.stderr.write('Exa TRAINING cell must not claim no-training: %r\\n' % (training,))
    sys.exit(1)
\""

# 12. NEOVIM SMOKE TEST
# pi-claude-auth → pi-claude-bridge migration. pi-claude-auth copied Claude
# Code's Keychain credential into pi's anthropic auth.json slot and re-synced it
# every 5 minutes, so pi and the claude CLI rotated the same refresh token.
# Route B: the bridge inherits Claude Code's own auth and stays INSTALLED for
# deliberate `--model claude-bridge/...` escalation, but the curated picker is
# opencode-go only. pi's native `/login` route is third-party-repriced and keeps
# no credential (docs/GOTCHAS.md), so an `anthropic/*` pin here would 400 or
# bill extra usage.
check_not "pi settings: pi-claude-auth package removed (migrated to claude-bridge)" \
    'pi-claude-auth' "$DOTFILES/base/pi/.pi/agent/settings.desired.json"

check_has "pi settings: claude-bridge declared as a package" \
    'npm:pi-claude-bridge' "$DOTFILES/base/pi/.pi/agent/settings.desired.json"

check "pi settings: curated picker is opencode-go only (bridge is explicit escalation)" \
    bash -c "python3 -c \"
import json, sys
s = json.load(open('$DOTFILES/base/pi/.pi/agent/settings.desired.json'))
bad = [m for m in s.get('enabledModels', []) if not m.startswith('opencode-go/')]
if bad:
    sys.stderr.write('non-Go entries in enabledModels: %r\\n' % (bad,))
    sys.exit(1)
\""

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
    '"edit", "write", "AskClaude", "subagent"' "$DOTFILES/base/pi/.pi/agent/extensions/optional/modes/index.ts"

# kimi left the roster (2 cycle entries) and /chat's model pin. One of the two
# entries (`opencode-go/kimi-k2.6`) no longer existed, so every pi start warned
# "No models match pattern". Tombstone both so they cannot creep back.
check_not "pi settings: kimi removed from the cycle set" \
    'kimi' "$DOTFILES/base/pi/.pi/agent/settings.desired.json"

# /chat must ride the bridge. pi's native OAuth direct route is third-party
# repriced whenever the request carries pi's harness system prompt, which every
# normal session does — a direct pin 400s on every chat turn.
check_has "pi modes: /chat pins the bridge model" \
    'provider: "claude-bridge", id: "claude-sonnet-5-5"' "$DOTFILES/base/pi/.pi/agent/extensions/optional/modes/index.ts"

# ...and the negative: a second, direct pin added alongside the bridge one would
# otherwise slip through the check above.
check_not "pi modes: no direct anthropic model pin" \
    'provider: "anthropic"' "$DOTFILES/base/pi/.pi/agent/extensions/optional/modes/index.ts"

check_not "pi modes: /chat no longer pins a kimi model" \
    'kimi' "$DOTFILES/base/pi/.pi/agent/extensions/optional/modes/index.ts"

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
d = json.load(open('$DOTFILES/base/pi/.pi/agent/settings.desired.json'))
# `defaultModel` is bare by contract (settings.md): a qualified id there is
# ignored at startup, so this pairing is what the checked-in default MEANS.
d = d.get('defaultProvider', '') + '/' + d['defaultModel']
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

# The provider-fallback map must point a real provider at a DIFFERENT one, and
# the committed default must not be a twin — an automatic hop does not persist
# (extension-facing pi.setModel passes no `persist`), so a twin sitting in
# defaultModel means either a deliberate /use or a pi upgrade that started
# persisting; both deserve a human look, not a silent commit.
check "pi: provider fallback maps a provider to a different one" \
    bash -c "python3 -c \"
import json, sys
s = json.load(open('$DOTFILES/base/pi/.pi/agent/settings.desired.json'))
pf = s.get('providerFallbacks') or {}
if not pf:
    sys.exit(1)
twins = set()
for prov, entry in pf.items():
    to = entry.get('to')
    if not to or to == prov or not entry.get('match'):
        sys.stderr.write('bad providerFallbacks entry: %r -> %r\\n' % (prov, entry))
        sys.exit(1)
    twins.add(to)
default = s.get('defaultModel', '')
qualified = s.get('defaultProvider', '') + '/' + default
if qualified.split('/')[0] in twins:
    sys.stderr.write('defaultModel %r is a fallback twin, not a primary\\n' % default)
    sys.exit(1)
\"" 

# Every agent pins a model, and the roster table documents each role. A pin
# swapped in an agent file but not reflected in the README — or a row left
# pointing at a model nobody pins — is the drift class the deepseek-v4/v4.1
# split thrived in.
# Matched as a BACKTICKED id, not a bare substring. A bare `m not in readme`
# was satisfied by the longer id of a related row: once `opencode-go/glm-5.3-flash`
# gained a roster row, deleting the oracle's `opencode-go/glm-5.3` row still passed.
check "pi: every agent model pin is documented in the README roster" \
    bash -c "python3 -c \"
import glob, sys
tick = chr(96)
readme = open('$DOTFILES/base/pi/README.md').read()
missing = []
for f in sorted(glob.glob('$DOTFILES/base/pi/.pi/agent/agents/*.md')):
    for line in open(f):
        if line.startswith('model: '):
            m = line[len('model: '):].strip()
            if tick + m + tick not in readme:
                missing.append(f.split('/')[-1] + ' -> ' + m)
            break
if missing:
    sys.stderr.write('undocumented agent pins: %s\\n' % ', '.join(missing))
    sys.exit(1)
\""

# Agents must request the hypa tools, not the builtins they replace: pi-hypa's
# replace filter drops a builtin only when its hypa twin is in the SAME tool
# list, so an agent asking for `bash` gets native bash. That is still gated —
# SHELL_TOOLS in lib/mutation-guard.ts lists "bash" and "hypa_shell", and the
# infra write-gate, the /check classifier and the publish guard all read that one
# list — but the hypa twin is what the rest of the stack (paths, truncation) is
# written against, so the agent lists stay hypa-only.
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
# Global AGENTS' recorded target was 138 words (TODO "prompt-slim watch"). The
# 2026-11-23 trim closed that gap by compressing four sections rather than deleting
# any, so the cap now sits at the target it was frozen above. A bump must name the
# incident behind it, same rule as APPEND.
_global_agents_words=$(wc -w < "$DOTFILES/base/pi/.pi/agent/AGENTS.md" | tr -d ' ')
check "pi: global AGENTS.md within its word budget ($_global_agents_words/138)" \
    test "$_global_agents_words" -le 138
_repo_agents_words=$(wc -w < "$DOTFILES/AGENTS.md" | tr -d ' ')
# 2026-11-23 (polling): a 24h session on glm-5.3 spent 7.5h asleep inside model
# turns — 156 `sleep` calls, $10.65 of polling, 42 cold re-entries at $0.157 each
# against $0.019 warm. The rule has to be always-on; detail moved to
# docs/POLLING.md to keep the bullet to one line. 1200 -> 1251.
check "repo AGENTS.md within its word budget ($_repo_agents_words/1251)" \
    test "$_repo_agents_words" -le 1251
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
check_has "pi-prune-sessions: default retention is 90 days" \
    'set -l days 90' "$_PI_PRUNE"
# The empty-dir sweep must run even when nothing is old enough: it used to sit
# AFTER the "nothing older" early return, so empty project dirs accumulated. The
# fresh transcript pins the other half — a sweep that ran `find` without -empty
# (or with a wider -type) would eat it.
if command -v fish >/dev/null 2>&1; then
    check "pi-prune-sessions: sweeps empty project dirs, keeps a fresh transcript" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            mkdir -p "$d/.pi/agent/sessions/emptyproj" "$d/.pi/agent/sessions/freshproj"
            : > "$d/.pi/agent/sessions/freshproj/fresh.jsonl"
            env HOME="$d" fish -N -c "source \"$1\"; pi-prune-sessions" >/dev/null 2>&1
            test ! -d "$d/.pi/agent/sessions/emptyproj" &&
            test -f "$d/.pi/agent/sessions/freshproj/fresh.jsonl"' \
        _ "$_PI_PRUNE"
    # The OTHER branch: a directory emptied BY this run (its only transcript was old
    # enough to delete) must be swept in the same run, not survive until the next.
    check "pi-prune-sessions: removes a dir emptied by THIS run" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            mkdir -p "$d/.pi/agent/sessions/oldproj"
            : > "$d/.pi/agent/sessions/oldproj/old.jsonl"
            touch -t 200001010000 "$d/.pi/agent/sessions/oldproj/old.jsonl"
            env HOME="$d" fish -N -c "source \"$1\"; pi-prune-sessions" >/dev/null 2>&1
            test ! -d "$d/.pi/agent/sessions/oldproj"' \
        _ "$_PI_PRUNE"
    # A fresh transcript in its own dir must survive the post-delete sweep too: a
    # sweep that lost its -empty guard (or ran without -type d) would eat it.
    check "pi-prune-sessions: the post-delete sweep keeps a fresh transcript" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            mkdir -p "$d/.pi/agent/sessions/oldproj" "$d/.pi/agent/sessions/freshproj"
            : > "$d/.pi/agent/sessions/oldproj/old.jsonl"
            touch -t 200001010000 "$d/.pi/agent/sessions/oldproj/old.jsonl"
            : > "$d/.pi/agent/sessions/freshproj/fresh.jsonl"
            env HOME="$d" fish -N -c "source \"$1\"; pi-prune-sessions" >/dev/null 2>&1
            test ! -d "$d/.pi/agent/sessions/oldproj" &&
            test -f "$d/.pi/agent/sessions/freshproj/fresh.jsonl"' \
        _ "$_PI_PRUNE"
fi

# ── pi settings: tracked template vs host-local live file ────────────────────
# pi persists runtime state (selected model, theme, thinking level,
# lastChangelogVersion, package list) into ~/.pi/agent/settings.json on every
# change. That path used to be a stow symlink into base/pi, so every session
# wrote through the link into a TRACKED file: any running session left the tree
# dirty, a commit made while one ran swept up whatever it had last selected, and
# hosts pulling the same branch fought over the same bytes. The split below ends
# the class:
#   base/pi/.pi/agent/settings.desired.json  tracked INTENT, stowed, never read
#                                            by pi — the assertions in this
#                                            section read THIS file, so they
#                                            stay valid on a CI checkout
#   ~/.pi/agent/settings.json                host-local live file, never stowed,
#                                            never tracked, written by pi
# pi 1.3.0 merges its own writes per top-level key under a lockfile, so
# concurrent sessions keep each other's UNRELATED keys. The residual upstream
# races (same-key last-write-wins, the first write to an absent file, a torn
# non-atomic write) are unchanged by this design — pi-settings-apply's header
# documents them, and nothing here claims to fix them.
section "Pi settings: template vs host-local live file"

_PI_SETTINGS_APPLY="$DOTFILES/base/fish/.config/fish/functions/pi-settings-apply.fish"
_PI_SETTINGS_TEMPLATE="$DOTFILES/base/pi/.pi/agent/settings.desired.json"

check "pi settings: template exists in base/pi" test -f "$_PI_SETTINGS_TEMPLATE"
# Tombstone: the tracked file must not be the live path again. If it returns,
# stow relinks it and every session dirties the repo — the class this ended.
check "pi settings: old tracked settings.json is gone (template is the only one)" \
    test ! -e "$DOTFILES/base/pi/.pi/agent/settings.json"
# Intent only: lastChangelogVersion is per-host state, so committing it would put
# a host-specific value back under version control.
check_not "pi settings: template declares no lastChangelogVersion (per-host state)" \
    'lastChangelogVersion' "$_PI_SETTINGS_TEMPLATE"
# Pi-Bolt compiles a `usage` extension in AND @tmustier/pi-usage-extension registers
# the same `/usage`, so bolt dropped the builtin and warned on EVERY invocation (on
# stderr, so scripted stdout stayed clean — noise, not breakage). The package is the
# canonical copy: it is the only one that exists under `pi-use pi`, so dropping it
# would lose /usage on the rollback path. The builtin is therefore switched off
# explicitly instead of left to "whichever loads"; upstream pi ignores an unknown
# `-builtin:<name>` silently (measured 2026-11-05), so one shared settings file is
# correct on both variants.
# Parsed, NOT grepped: the string appearing anywhere would satisfy a text pin, and
# what matters is that `extensions` holds EXACTLY this decision (an added entry is a
# second disable the template did not intend).
# The two load entries are the OPTIONAL axis. pi discovers only extensions/*.ts and
# extensions/*/index.ts, so moving infra-safety + modes under extensions/optional/
# made them opt-in: this list is how a laptop opts in, and the agentbox profile is
# how an appliance opts out. Paths are agentDir-relative because pi resolves them
# against ~/.pi/agent itself (and persists them in that form).
check "pi settings: the template's extensions list is exactly [-builtin:usage + the optional axis]" \
    python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("extensions") == ["-builtin:usage", "extensions/optional/infra-safety.ts", "extensions/optional/modes"] else 1)' \
    "$_PI_SETTINGS_TEMPLATE"
# ...and each of those load entries must resolve. pi drops a missing path with NO
# diagnostic, so a typo or a second move would silently remove L2 and /check from
# every host that applies this template. Stow puts base/pi/.pi/agent AT ~/.pi/agent,
# so this is a faithful model of pi's own resolution, and it runs in CI.
check "pi settings: every extensions entry resolves inside the agent dir" \
    python3 -c 'import json,os,sys
tpl, agent = sys.argv[1], sys.argv[2]
missing = [e for e in (json.load(open(tpl)).get("extensions") or [])
           if not e.startswith("-") and not os.path.exists(os.path.join(agent, e))]
if missing:
    sys.stderr.write("unresolved extensions entries: %r\n" % (missing,)); sys.exit(1)' \
    "$_PI_SETTINGS_TEMPLATE" "$DOTFILES/base/pi/.pi/agent"
# The package half is the load-bearing one: it guards the REJECTED alternative
# (dropping the npm package and relying on bolt's undocumented builtin, which would
# remove /usage under `pi-use pi`), and nothing else asserts it.
check_has "pi settings: the usage package is still declared (canonical on both variants)" \
    'npm:@tmustier/pi-usage-extension' "$_PI_SETTINGS_TEMPLATE"
# L3 (cc-safety-net) is a settings PACKAGE, so the template is what puts it on a host:
# probe C measured that a declared `npm:` entry is auto-installed into <agent-dir>/npm,
# which is why no installer step exists. Pinned to a full semver, and exactly one
# entry: a floating range would move a safety layer without a reviewable diff, and a
# second entry would be two versions of the same rules.
check "pi settings: cc-safety-net is declared once, pinned to a full semver" \
    python3 -c '
import json, re, sys
pkgs = json.load(open(sys.argv[1])).get("packages") or []
hits = [p for p in pkgs if p.startswith("npm:cc-safety-net")]
sys.exit(0 if len(hits) == 1 and re.fullmatch(r"npm:cc-safety-net@[0-9]+\.[0-9]+\.[0-9]+", hits[0]) else 1)
' "$_PI_SETTINGS_TEMPLATE"
# The same reasoning now covers EVERY package: a floating `npm:` entry, or a `git:`
# source with no ref, moves code (and, for ponytail, prompt text) into every
# session with no reviewable diff. The pin is the review gate; the version bump is
# the commit.
check "pi settings: every package is pinned (semver, or a 40-hex git ref)" \
    python3 -c '
import json, re, sys
pkgs = json.load(open(sys.argv[1])).get("packages") or []
bad = []
for p in pkgs:
    if p.startswith("npm:"):
        if not re.fullmatch(r"npm:(@[^/]+/)?[^@]+@[0-9]+\.[0-9]+\.[0-9]+", p):
            bad.append(p)
    elif p.startswith("git:"):
        if not re.search(r"@[0-9a-f]{40}$", p):
            bad.append(p)
    else:
        bad.append(p)
if bad:
    sys.stderr.write("unpinned package(s): " + ", ".join(bad) + chr(10))
    sys.exit(1)
' "$_PI_SETTINGS_TEMPLATE"
# User-scope agent skills have two provenance classes and both must be visible:
# the skills manager records what it installed (source + commit per skill) in
# ~/.agents/.skill-lock.json, and the Paseo app ships its own. Anything else on
# disk is unmanaged drift — a hand-copied skill that no update path replaces and
# no diff ever reviews. Host-local: skipped where the directory is absent (CI).
_AGENTS_SKILLS_NAME="agents: every user-scope skill has a recorded source (lock or app)"
if [ ! -d "$HOME/.agents/skills" ]; then
    # No user-scope skills on this host (CI image): say so, do not report a pass.
    _skip "$_AGENTS_SKILLS_NAME" "no ~/.agents/skills on this host"
else
    check "$_AGENTS_SKILLS_NAME" bash -c "python3 -c \"
import json, os, sys
root = os.path.join(os.environ['HOME'], '.agents', 'skills')
dirs = sorted(d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d)))
try:
    locked = json.load(open(os.path.join(os.environ['HOME'], '.agents', '.skill-lock.json'))).get('skills', {})
except OSError:
    locked = {}
# Paseo ships its own skills and records nothing here; anything ELSE without a
# lock entry is a hand copy no update path replaces.
bad = [d for d in dirs if d not in locked and not d.startswith('paseo')]
if bad:
    sys.stderr.write('unmanaged skill dir(s): ' + ', '.join(bad) + chr(10))
    sys.exit(1)
\""
fi
# PIG_USE_PI_DIRS travels with the shared dir, so a value here would make the
# ROLLBACK binary (upstream pi, and pi-bolt) carry a PiG-only key. It belongs in
# conf.d/pig.fish, where it applies to the shell that launches either harness.
check_not "pi settings: the template carries no PiG-only key (PIG_USE_PI_DIRS)" \
    'PIG_USE_PI_DIRS' "$_PI_SETTINGS_TEMPLATE"
check "pi settings: template is tracked by git" \
    git -C "$DOTFILES" ls-files --error-unmatch base/pi/.pi/agent/settings.desired.json
# The migration must recognise stow's RELATIVE link (../../dotfiles/...): a raw
# readlink never starts with an absolute $DOTFILES prefix, so a prefix test on it
# leaves every real host unmigrated while reporting success.
check_has "bootstrap: pi settings migration resolves the link target first" \
    'os\.path\.realpath' "$DOTFILES/bootstrap.sh"
check "bootstrap: pi settings migration runs after the stow block" \
    bash -c 'm=$(grep -n "^ *migrate_pi_settings_desync$" "$1" | tail -1 | cut -d: -f1)
        s=$(grep -n "stow_dir \"\$DOTFILES/base\"" "$1" | head -1 | cut -d: -f1)
        test -n "$m" && test -n "$s" && test "$m" -gt "$s"' _ "$DOTFILES/bootstrap.sh"
# Functional, through the real function: a relative stow link becomes a regular
# file holding the target's bytes. Sourcing with main "$@" stripped is the only
# way to reach an internal bootstrap function; the top-level is pure definition.
check_full "bootstrap: pi settings migration de-references a relative stow link" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
        mkdir -p "$d/dotfiles/base/pi/.pi/agent" "$d/.pi/agent"
        printf "%s" "{\"defaultModel\": \"mig\"}" > "$d/dotfiles/base/pi/.pi/agent/settings.desired.json"
        ln -s ../../dotfiles/base/pi/.pi/agent/settings.desired.json "$d/.pi/agent/settings.json"
        sed "/^main \"\$@\"$/d" "$1" > "$d/bootstrap.sh" || exit 1
        env HOME="$d" PATH="${_MISE_REAL_BINS:+$_MISE_REAL_BINS:}$PATH" DOTFILES="$d/dotfiles" bash -c "source \"$d/bootstrap.sh\"; migrate_pi_settings_desync" >/dev/null 2>&1 || exit 1
        test -f "$d/.pi/agent/settings.json" || exit 1
        test ! -L "$d/.pi/agent/settings.json" || exit 1
        grep -q "\"defaultModel\": \"mig\"" "$d/.pi/agent/settings.json" || exit 1
        exit 0' _ "$DOTFILES/bootstrap.sh"
# The live file must not be a symlink into this repo. Absent is a LOUD skip: CI
# has no live pi state, and silence would hide that the check never ran.
if [[ -e "$HOME/.pi/agent/settings.json" || -L "$HOME/.pi/agent/settings.json" ]]; then
    # python realpath, not readlink -f: the latter is macOS 12.3+ only and this
    # suite runs on mbpm3 too (bootstrap avoids it for the same reason).
    check "pi settings: live settings.json is host-local, not a stow link" \
        bash -c '[ ! -L "$1" ] || ! python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1" | grep -qF "$2"' _ \
        "$HOME/.pi/agent/settings.json" "$DOTFILES"
else
    _skip "pi settings: live settings.json is host-local, not a stow link" \
        "no live pi settings on this host (CI)"
fi

check "pi-settings-apply: function exists in base/fish" test -f "$_PI_SETTINGS_APPLY"
check "pi-settings-reset: the old function does not reappear" \
    test ! -e "$DOTFILES/base/fish/.config/fish/functions/pi-settings-reset.fish"
# The fish .gitignore is an allowlist, so a new own-file silently drops out of the
# repo without this.
if command -v fish >/dev/null 2>&1; then
    check "pi-settings-apply: parses (fish -n)" \
        fish -n "$_PI_SETTINGS_APPLY"
fi
# The merge policy is asserted on the code as well as behaviourally: the
# functional tests below can only pin one case each.
check_has "pi-settings-apply: template wins per top-level key" \
    'for k in template:' "$_PI_SETTINGS_APPLY"
# ...except packages, where a live `pi install` / `pi remove` must survive
# (silently reverting a deliberate act is the bug the old keep-set existed for).
check_has "pi-settings-apply: packages is live-wins (a pi install is deliberate)" \
    'if k == "packages" and k in live:' "$_PI_SETTINGS_APPLY"
# ...while live-only keys survive by default, which is what makes the per-host
# lastChangelogVersion safe with no keep-list in the function.
check_has "pi-settings-apply: live-only keys are preserved unless --prune" \
    'if not PRUNE:' "$_PI_SETTINGS_APPLY"
# A stow symlink would put the write in the repo — the exact failure this exists
# to end — so a real write refuses it; a dry run may still read through it.
check_has "pi-settings-apply: refuses to write through a stow symlink" \
    'a stow link puts the write in the repo' "$_PI_SETTINGS_APPLY"
# The keep-set is gone on purpose: preservation-by-default replaced it, so its
# return would be a design regression, not a feature.
check_not "pi-settings-apply: no keep-set reappears (preservation made it moot)" \
    'KEEP = ' "$_PI_SETTINGS_APPLY"
check_has "pi-settings-apply: writes atomically (os.replace)" \
    'os\.replace\(tmp, live_path\)' "$_PI_SETTINGS_APPLY"
check_has "pi-settings-apply: verifies exact bytes after writing" \
    'if now == out:' "$_PI_SETTINGS_APPLY"
check_has "pi-settings-apply: bounds the retry loop" \
    'for attempt in range\(3\)' "$_PI_SETTINGS_APPLY"
check_has "pi-settings-apply: treats a torn write as recoverable, not an error" \
    'except json\.JSONDecodeError' "$_PI_SETTINGS_APPLY"
check_has "pi-settings-apply: an unreadable file is archived, not silently replaced" \
    'settings\.json\.unparsable-' "$_PI_SETTINGS_APPLY"
check_has "pi-settings-apply: rejects non-object JSON too" \
    'JSON but not an object' "$_PI_SETTINGS_APPLY"
check_has "pi-settings-apply: a retry-path torn write is archived, not dropped" \
    'torn_backup = archive_bytes\(raw2\)' "$_PI_SETTINGS_APPLY"
check_has "pi-settings-apply: a missing live file is created from the template (code)" \
    'fresh = not os\.path\.lexists\(live_path\)' "$_PI_SETTINGS_APPLY"

if command -v fish >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    # The whole functional group is gated: each check runs the real fish helper
    # through python3 under a throwaway dir, which is ~200ms apiece.
    if _full; then
    # Functional, through the helper with explicit paths, so the real agent dir is
    # never touched. Policy under test: template wins, packages live-wins,
    # live-only preserved, --prune drops, -n writes nothing, the rewrite stays in
    # pi's format (no trailing newline), and a torn file is archived then rebuilt.
    check "pi-settings-apply: template wins, packages live-wins, live-only preserved" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            t="$d/template.json"; l="$d/live.json"
            printf "%s" "{\"defaultModel\": \"tpl\", \"packages\": [\"npm:x\"]}" > "$t"
            printf "%s" "{\"defaultModel\": \"live\", \"packages\": [\"npm:x\", \"npm:y\"], \"lastChangelogVersion\": \"9\"}" > "$l"
            fish -c "source \"$1\"; __pi_settings_apply \"$t\" \"$l\" 0 0" >/dev/null 2>&1 || exit 1
            grep -q "\"defaultModel\": \"tpl\"" "$l" &&
            grep -q "npm:y" "$l" &&
            grep -q "lastChangelogVersion" "$l" &&
            test -n "$(tail -c 1 "$l")"' _ "$_PI_SETTINGS_APPLY"
    check "pi-settings-apply: --prune drops live-only keys" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            t="$d/template.json"; l="$d/live.json"
            printf "%s" "{\"defaultModel\": \"tpl\"}" > "$t"
            printf "%s" "{\"defaultModel\": \"live\", \"hostOnly\": true}" > "$l"
            fish -c "source \"$1\"; __pi_settings_apply \"$t\" \"$l\" 0 1" >/dev/null 2>&1 || exit 1
            ! grep -q hostOnly "$l" &&
            grep -q "\"defaultModel\": \"tpl\"" "$l"' _ "$_PI_SETTINGS_APPLY"
    # -n is the promote worklist, so its exit code has to be a faithful predictor
    # of "apply would change something" while writing nothing itself.
    check "pi-settings-apply: -n exits 1 on drift, 0 when identical, writes nothing" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            t="$d/template.json"; l="$d/live.json"
            printf "%s" "{\"defaultModel\": \"tpl\"}" > "$t"
            printf "%s" "{\"defaultModel\": \"live\"}" > "$l"
            h=$(shasum "$l")
            fish -c "source \"$1\"; __pi_settings_apply \"$t\" \"$l\" 1 0" >/dev/null 2>&1
            test $? -eq 1 || exit 1
            test "$(shasum "$l")" = "$h" || exit 1
            fish -c "source \"$1\"; __pi_settings_apply \"$t\" \"$l\" 0 0" >/dev/null 2>&1 || exit 1
            fish -c "source \"$1\"; __pi_settings_apply \"$t\" \"$l\" 1 0" >/dev/null 2>&1
            test $? -eq 0' _ "$_PI_SETTINGS_APPLY"
    # A fresh host has no live file: bootstrap must end with one, without a pi run.
    check "pi-settings-apply: a missing live file is created from the template" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            t="$d/template.json"; l="$d/live.json"
            printf "%s" "{\"defaultModel\": \"tpl\"}" > "$t"
            fish -c "source \"$1\"; __pi_settings_apply \"$t\" \"$l\" 0 0" >/dev/null 2>&1 || exit 1
            grep -q "\"defaultModel\": \"tpl\"" "$l"' _ "$_PI_SETTINGS_APPLY"
    # A torn pi write must hand the unreadable bytes back rather than drop them.
    check "pi-settings-apply: an unparsable live file is archived, then rebuilt" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            t="$d/template.json"; l="$d/live.json"
            printf "%s" "{\"defaultModel\": \"tpl\"}" > "$t"
            printf "%s" "{\"defaultModel\": \"tpl\", \"packa" > "$l"
            fish -c "source \"$1\"; __pi_settings_apply \"$t\" \"$l\" 0 0" >/dev/null 2>&1
            test $? -eq 1 || exit 1
            ls "$d"/settings.json.unparsable-* >/dev/null 2>&1 || exit 1
            grep -q "packa" "$d"/settings.json.unparsable-* || exit 1
            grep -q "\"defaultModel\": \"tpl\"" "$l"' _ "$_PI_SETTINGS_APPLY"
    # The pre-migration state: a leftover stow link must be refused as a WRITE
    # target (that write lands in the repo) while -n still reads through it, so
    # the delta stays inspectable before the link is replaced.
    check "pi-settings-apply: write refuses a stow symlink; -n reads through it" \
        bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
            t="$d/template.json"; c="$d/canon.json"; r="$d/repo.json"; l="$d/live.json"
            printf "%s" "{\"defaultModel\": \"tpl\"}" > "$t"
            # canonical bytes first: -n compares BYTES, so a compact fixture would
            # report cosmetic drift and mask what this asserts (a read-through).
            fish -c "source \"$1\"; __pi_settings_apply \"$t\" \"$c\" 0 0" >/dev/null 2>&1 || exit 1
            cp "$c" "$r"; ln -s "$r" "$l"
            fish -c "source \"$1\"; __pi_settings_apply \"$t\" \"$l\" 0 0" >/dev/null 2>&1
            test $? -eq 1 || exit 1
            test -L "$l" || exit 1
            fish -c "source \"$1\"; __pi_settings_apply \"$t\" \"$l\" 1 0" >/dev/null 2>&1
            test $? -eq 0' _ "$_PI_SETTINGS_APPLY"
    check "pi-settings-apply: public wrapper rejects a bad argument (exit 2)" \
        bash -c 'fish -c "source \"$1\"; pi-settings-apply --bogus" >/dev/null 2>&1; test $? -eq 2' \
        _ "$_PI_SETTINGS_APPLY"
    else
        _defer 7
    fi
else
    _skip "pi-settings-apply: functional tests" "fish + python3 not both callable in this env"
fi

# ── repo-list ────────────────────────────────────────────────────────────────
# Its own section, because repo-list is navigation, not workstreams: it outlived pwt and
# must not be swept away with any future reorganisation of this file — 10 checks here,
# seven of them full-mode-only.
section "repo-list"

# The rule is subtle enough to have been got wrong twice during development, so each
# branch is asserted directly.
_RL="$DOTFILES/base/tmux/bin/repo-list"
check "repo-list: helper exists in base/tmux/bin" test -f "$_RL"
check "repo-list: is executable" test -x "$_RL"
check_full "repo-list: shellcheck clean" shellcheck -S warning "$_RL"
check_full "repo-list: runs under /bin/bash (3.2 on macOS)" \
    env WT_SRC="$DOTFILES/.git" /bin/bash "$_RL" --stdin < /dev/null
check_full "repo-list: keeps a repo root, drops its subdirectories" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT; cd "$d"; git init -q; mkdir -p sub/deep
        out=$(printf "%s\n%s\n%s\n" "$d" "$d/sub" "$d/sub/deep" | "$1" --stdin)
        [[ "$out" == "$d" ]]' _ "$_RL"
check_full "repo-list: keeps a path that is in no repo (nothing hidden)" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT; mkdir -p "$d/standalone"
        out=$(printf "%s\n" "$d/standalone" | "$1" --stdin)
        [[ "$out" == "$d/standalone" ]]' _ "$_RL"
check_full "repo-list: drops .git and __worktrees paths" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT; cd "$d"; git init -q
        out=$(printf "%s\n%s\n" "$d/.git" "$d/__worktrees/x" | "$1" --stdin)
        [[ -z "$out" ]]' _ "$_RL"
# The two navigation roots must not depend on zoxide still holding a score for
# them: a fresh WT_SRC has no zoxide entries at all, so this exercises the
# always-emit path. Home first, source root last (outer -> inner).
check_full "repo-list: always offers ~ and the source root, in that order" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
        out=$(WT_SRC="$d" "$1" 2>/dev/null)
        [[ "$(printf "%s\n" "$out" | head -1)" == "$HOME" ]] &&
        [[ "$(printf "%s\n" "$out" | tail -1)" == "$d" ]]' _ "$_RL"
check_full "repo-list: --stdin filters exactly the given list (no injection)" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
        out=$(printf "" | WT_SRC="$d" "$1" --stdin)
        [[ -z "$out" ]]' _ "$_RL"
# --stdin must pass paths through untouched: skipping $HOME/$SRC there (they are
# skipped in zoxide mode to avoid re-emitting them) silently dropped input lines.
check "repo-list: --stdin passes the roots through unchanged" \
    bash -c 'out=$(printf "%s\n%s\n" "$HOME" "$1" | "$2" --stdin)
        [[ "$out" == "$HOME"$'"'"'\n'"'"'"$1" ]]' _ "$HOME/src" "$_RL"

# ── worktrunk (wt) ───────────────────────────────────────────────────────────
# wt owns git worktrees; it does NOT own tmux windows, session ids or agent state.
# Two upstream facts drive the shape here, and neither is visible from the code that
# depends on them: worktrunk writes no info/exclude (so __worktrees/ would pollute git
# status), and its post-start hook runs in the BACKGROUND with no template variables in
# the environment. The wt-free block below is the real guard — CI installs no mise, so
# every wt-gated check is merely deferred there.
section "worktrunk (wt)"

_WT_PKG="$DOTFILES/base/worktrunk"
_WT_CFG="$_WT_PKG/.config/worktrunk/config.toml"
_WT_EXCL="$_WT_PKG/bin/wt-exclude"
_WT_DOC="$DOTFILES/docs/WT.md"
_WT_MISE="$DOTFILES/base/mise/.config/mise/config.toml"

check_has "wt: worktrees land inside the repo at __worktrees/" \
    '^worktree-path = ".*__worktrees/' "$_WT_CFG"
check "wt: a user post-start hook runs wt-exclude" bash -c \
    'grep -A1 -x "\[post-start\]" "$1" | grep -q "^exclude = .*wt-exclude"' _ "$_WT_CFG"
check "wt: wt-exclude is executable (an unrunnable hook fails silently)" \
    test -x "$_WT_EXCL"
check_has "wt: mise pins worktrunk at an exact version" \
    '^"aqua:max-sixty/worktrunk" = "[0-9]+\.[0-9]+\.[0-9]+"$' "$_WT_MISE"
check "wt: bootstrap stows the package" \
    bash -c 'grep -q "stow_dir.*DOTFILES/base.*worktrunk" "$1"' _ "$DOTFILES/bootstrap.sh"
# The surviving contract needs a pointer from AGENTS.md, which is the map: an unlinked
# doc goes unread.
check_has "AGENTS.md: points at docs/WT.md" 'docs/WT\.md' "$DOTFILES/AGENTS.md"
check_has "wt: the contract forbids --force" 'Never `wt remove --force`' "$_WT_DOC"
check_has "wt: the contract warns that ignored files are deleted" \
    'Ignored files are not protection' "$_WT_DOC"
check_not "wt: the contract cites no host-local plan" '\.pi/plans' "$_WT_DOC"

# Tombstones. The REMOVAL is load-bearing: two workstream models in one tmux server is
# exactly the failure pwt existed to prevent (two agents on one session, silently losing
# turns), so every piece that could come back gets a check rather than a comment.
_WT_TMUX="$DOTFILES/base/tmux/.config/tmux/tmux.conf"
check "wt: the pwt function is gone" \
    test ! -e "$DOTFILES/base/fish/.config/fish/functions/pwt.fish"
check "wt: its completion is gone" \
    test ! -e "$DOTFILES/base/fish/.config/fish/completions/pwt.fish"
check "wt: the panel, tap, preview and revive scripts are gone" bash -c \
    'for f in pwt-pick pwt-osc pwt-preview pwt-revive-restored; do
        [ -e "$1/base/tmux/bin/$f" ] && exit 1
     done; exit 0' _ "$DOTFILES"
check "wt: docs/PWT.md is gone" test ! -e "$DOTFILES/docs/PWT.md"
check_not "wt: no pwt-era state flag survives in tmux.conf" \
    '@pwt_|@pi_alert|@pi_state|PI_PROGRAM_STATUS' "$_WT_TMUX"
check_has "wt: the bar flag is pi's own (@pi_waiting, not the retired tap)" \
    '@pi_waiting' "$_WT_TMUX"
# C-f's binding wraps onto a continuation line, so this greps the LINE AFTER it rather
# than assuming one line — the shape that made the first version of this check pass
# vacuously against nothing.
check "wt: C-f still reaches repo-list (navigation outlived the panel)" bash -c \
    'grep -A1 "^bind-key C-f " "$1" | grep -q "repo-list"' _ "$_WT_TMUX"
# The panel's BINARY is what must not come back (asserted above); the KEY was reused by
# its replacement, so this pins the successor rather than forbidding the binding.
check_has "wt: C-w runs the cross-repo view" '^bind-key C-w .*wt-all' "$_WT_TMUX"
check_not "wt: no post-restore revive hook survives" \
    'resurrect-hook-post-restore-all' "$_WT_TMUX"

# The wt-free guard. It drives the script itself, so it runs in CI — where every
# wt-gated check is deferred — and it is the only guard on the newline pad now that pwt's
# _full fixtures are gone. Exact bytes after two runs pins three
# properties in one assertion: the pad, the single line (idempotence), no blank line.
_wt_d=$(mktemp -d)
trap 'rm -rf "$_wt_d"' EXIT
git init -q "$_wt_d/pad"
printf 'node_modules/' > "$_wt_d/pad/.git/info/exclude"    # no trailing newline: the trap
( cd "$_wt_d/pad" && "$_WT_EXCL" && "$_WT_EXCL" )
check "wt-exclude: pads a newline-less last line, writes __worktrees/ once, run twice" \
    bash -c 'printf "node_modules/\n__worktrees/\n" | cmp -s - "$1"' _ "$_wt_d/pad/.git/info/exclude"
check "wt-exclude: node_modules/ is still ignored after the pad" \
    git -C "$_wt_d/pad" check-ignore -q node_modules/x
mkdir -p "$_wt_d/pad/__worktrees/demo"
printf 'x\n' > "$_wt_d/pad/__worktrees/demo/f"
check "wt-exclude: __worktrees/ stays out of status AND out of add -A" bash -c \
    'cd "$1" && ! git status --porcelain | grep -q __worktrees &&
     git add -A && ! git ls-files | grep -q __worktrees' _ "$_wt_d/pad"

# End to end through the real binary: full mode only (it creates a worktree and waits for
# a background hook), and only with a USABLE wt — command -v is not enough, since a mise
# shim with no version selected answers "No version is set for shim", and WSL leaks
# Windows Terminal's wt.exe through interop.
_wt_usable=0
case $(command -v wt 2>/dev/null) in
    ""|/mnt/*) ;;
    *) wt --version >/dev/null 2>&1 && _wt_usable=1 ;;
esac
# Both fixtures below run the binary under a SCRATCH HOME (that is the point: no user
# worktrunk config). A mise shim resolves WHICH version from $HOME, so there it answers
# "wt is not a valid shim" while `wt --version` passes under the real HOME — the fixture
# then creates nothing and two checks fail for a reason that has nothing to do with wt.
# Resolve the real binary once, the way pi-use does, and run that.
_wt_bin=$(command -v wt 2>/dev/null || true)
if [ "$_wt_usable" = 1 ] && command -v mise >/dev/null 2>&1; then
    _wt_real=$(mise which wt 2>/dev/null | tail -1)
    [ -n "$_wt_real" ] && [ -x "$_wt_real" ] && _wt_bin=$_wt_real
fi
if _full && [ "$_wt_usable" = 1 ]; then
    _wt_h="$_wt_d/home"
    _wt_r="$_wt_h/repo"
    mkdir -p "$_wt_h/bin" "$_wt_h/.config/worktrunk"
    ln -s "$_WT_EXCL" "$_wt_h/bin/wt-exclude"
    cp "$_WT_CFG" "$_wt_h/.config/worktrunk/config.toml"
    git init -q -b main "$_wt_r"
    printf 'base\n' > "$_wt_r/a.txt"
    git -C "$_wt_r" add -A
    git -C "$_wt_r" -c commit.gpgsign=false -c user.email=c@example.invalid \
        -c user.name=c commit -qm init
    ( cd "$_wt_r" && HOME="$_wt_h" XDG_CONFIG_HOME="$_wt_h/.config" \
        "$_wt_bin" switch --create demo --base @ --no-cd </dev/null >/dev/null 2>&1 )
    check "wt: the binary creates __worktrees/demo (precondition for the next check)" \
        test -d "$_wt_r/__worktrees/demo"
    _wt_ok=0
    for _wt_i in 1 2 3 4 5 6 7 8 9 10; do
        if ! git -C "$_wt_r" status --porcelain 2>/dev/null | grep -q __worktrees; then
            _wt_ok=1; break
        fi
        sleep 1
    done
    check "wt: the post-start hook keeps __worktrees/ out of git status" \
        test "$_wt_ok" = 1
else
    _defer 2
fi

# ── settle notify (pi extension) ─────────────────────────────────────────────
# The one behaviour worth keeping from the retired workstream helper: a desktop push when
# an agent wants a human. Three things are asserted because each fails SILENTLY — the
# wrong event (agent_end fires mid-task, so the push would lie), a message spliced into
# script text (breaks on the first quote), and a transport error reaching the session.
section "settle notify (pi extension)"

_SN="$DOTFILES/base/pi/.pi/agent/extensions/settle-notify.ts"
check "settle-notify: the extension exists" test -f "$_SN"
check_has "settle-notify: subscribes to agent_settled (the final-idle event)" \
    'pi\.on\("agent_settled"' "$_SN"
check_not "settle-notify: never subscribes to agent_end or turn_end (both fire mid-task)" \
    'pi\.on\("agent_end"|pi\.on\("turn_end"' "$_SN"
check_has "settle-notify: skips an aborted run (Escape means the human is there)" \
    'event\.aborted' "$_SN"
check_has "settle-notify: covers a blocking prompt too" \
    'pi\.on\("ui_prompt_start"' "$_SN"
check_has "settle-notify: an explicit mute switch exists" 'PI_SETTLE_NOTIFY' "$_SN"
check_has "settle-notify: has a transport seam, so the suite sends no real push" \
    'SETTLE_NOTIFY_CMD' "$_SN"
check_has "settle-notify: PowerShell text is base64, never script source" \
    'FromBase64String' "$_SN"
check_not "settle-notify: stays deployment-agnostic in the shared core" \
    'pwt|dotfiles' "$_SN"
check_has "settle-notify: documented in the pi README" 'settle-notify' \
    "$DOTFILES/base/pi/README.md"
# The second surface is the tmux bar, and it must stay pi's: the flag is raised on the same
# events, cleared when a run starts, and only the PUSH honours the mute.
check_has "settle-notify: raises @pi_waiting for the bar" \
    'FLAG = "@pi_waiting"' "$_SN"
check_has "settle-notify: clears it when a run starts (work resumed)" \
    'pi\.on\("agent_start"' "$_SN"
check_has "settle-notify: the mute silences only the push, not the bar" \
    'if \(MUTE\) return' "$_SN"
check_has "tmux: the bar renders the waiting flag as ASCII !" \
    'window-status-format.*@pi_waiting.*!' "$_WT_TMUX"
check_has "tmux: an ordinary window switch clears the flag" \
    "after-select-window 'set-window-option -u @pi_waiting'" "$_WT_TMUX"

# ── wt-all (cross-repo view) ─────────────────────────────────────────────────
# The cross-repo half of the retired panel, rebuilt as a READER: rows come from `wt list`
# per repo, so there is no second state store to drift. Two things it must not do — keep
# its own notion of a workstream, or spawn an agent (starting one is `creds pi -c` in the
# window it opens, which is what keeps wt out of session ids).
section "wt-all (cross-repo view)"

_WTA="$DOTFILES/base/tmux/bin/wt-all"
check "wt-all: exists in base/tmux/bin" test -f "$_WTA"
check "wt-all: is executable" test -x "$_WTA"
check_has "wt-all: reads wt's own JSON, not a second state store" \
    'wt list --format=json' "$_WTA"
check_has "wt-all: reads the same source root as repo-list (WT_SRC, then ~/src)" \
    'WT_SRC:-\$HOME/src' "$_WTA"
check_has "wt-all: refuses loudly without wt rather than showing an empty view" \
    'wt not on PATH' "$_WTA"
check_has "wt-all: the picker opens a WINDOW, not an agent" \
    'tmux new-window -c' "$_WTA"
check_not "wt-all: never spawns an agent (no session id, no pi invocation)" \
    'pi --|pi -c|--session-id' "$_WTA"
check_has "wt-all: a path with spaces survives the picker (quoted placeholder)" \
    'git -C \{5\} status' "$_WTA"

if _full && command -v wt >/dev/null 2>&1 && wt --version >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    _wta_d=$(mktemp -d)
    # One trap for both temp trees: a second `trap ... EXIT` REPLACES the first, which
    # would silently orphan the wt section's directory.
    trap 'rm -rf "${_wt_d:-}" "${_wta_d:-}"' EXIT
    mkdir -p "$_wta_d/home/.config/worktrunk"
    printf 'worktree-path = "{{ repo_path }}/__worktrees/{{ branch | sanitize }}"\n' \
        > "$_wta_d/home/.config/worktrunk/config.toml"
    for _wta_r in alpha beta; do
        git init -q -b main "$_wta_d/$_wta_r"
        printf 'x\n' > "$_wta_d/$_wta_r/f"
        git -C "$_wta_d/$_wta_r" add -A
        git -C "$_wta_d/$_wta_r" -c commit.gpgsign=false -c user.email=c@example.invalid \
            -c user.name=c commit -qm init
        ( cd "$_wta_d/$_wta_r" && HOME="$_wta_d/home" XDG_CONFIG_HOME="$_wta_d/home/.config" \
            "$_wt_bin" switch --create "$_wta_r-ws" --base @ --no-cd >/dev/null 2>&1 )
    done
    _wta_out=$(WT_SRC="$_wta_d" "$_WTA" --list 2>/dev/null)
    check "wt-all: merges a worktree from every repo under the source root" bash -c \
        'printf "%s" "$1" | grep -q "alpha-ws" && printf "%s" "$1" | grep -q "beta-ws"' _ "$_wta_out"
    check "wt-all: each row carries the worktree path, not its repo root" bash -c \
        'printf "%s" "$1" | grep -q "/alpha/__worktrees/alpha-ws"' _ "$_wta_out"
else
    _defer 2
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

# ── git-prune-merged ─────────────────────────────────────────────────────────
# The branch-hygiene half of the manual tooling. Only `--merged` is a safe gate:
# an abandoned PR's branch shows a [gone] upstream but its commits are NOT in the
# base, so a [gone]-driven prune would throw them away. The fixture spells out all
# four cases — merged+checked-out, merged+deletable, unmerged, and unmerged with a
# gone upstream — and proves dry-run is inert and --apply removes exactly one.
# Fabricated repo ONLY: never the developer's.
section "git-prune-merged"

_GIT_PRUNE="$DOTFILES/base/fish/.config/fish/functions/git-prune-merged.fish"
check "git-prune-merged: function exists in base/fish" test -f "$_GIT_PRUNE"
check_has "git-prune-merged: candidates come from --merged" \
    'branch --merged' "$_GIT_PRUNE"
check_has "git-prune-merged: excludes branches held by worktrees" \
    'worktree list --porcelain' "$_GIT_PRUNE"
check_has "git-prune-merged: --apply uses branch -d" \
    'branch -d' "$_GIT_PRUNE"
check_not "git-prune-merged: never force-deletes (no branch -D)" \
    'branch -D' "$_GIT_PRUNE"
check_has "git-prune-merged: --fetch runs git fetch --prune" \
    'fetch --prune' "$_GIT_PRUNE"
if command -v fish >/dev/null 2>&1; then
    check "git-prune-merged: parses (fish -n)" fish -n "$_GIT_PRUNE"

    if _full; then
    _gp="$(mktemp -d)"
    _gp_repo="$_gp/repo"
    _gp_bare="$_gp/origin.git"
    git init -q -b main "$_gp_repo"
    git -C "$_gp_repo" config user.email t@t
    git -C "$_gp_repo" config user.name t
    echo base > "$_gp_repo/f"; git -C "$_gp_repo" add f
    git -C "$_gp_repo" -c commit.gpgsign=false commit -qm base
    # merged-worktree: merged into main but held by a LINKED worktree. HEAD stays
    # on main so `git branch -d` can succeed at all — it merges against HEAD, not
    # the base — which is exactly why the deletable branch must NOT be checked out.
    git -C "$_gp_repo" checkout -q -b merged-worktree
    echo w > "$_gp_repo/w"; git -C "$_gp_repo" add w
    git -C "$_gp_repo" -c commit.gpgsign=false commit -qm w
    git -C "$_gp_repo" checkout -q main
    git -C "$_gp_repo" merge -q --ff-only merged-worktree
    git -C "$_gp_repo" worktree add -q "$_gp/wt" merged-worktree
    # merged-deletable: merged into main, checked out nowhere (must be deleted)
    git -C "$_gp_repo" checkout -q -b merged-deletable
    echo d > "$_gp_repo/d"; git -C "$_gp_repo" add d
    git -C "$_gp_repo" -c commit.gpgsign=false commit -qm d
    git -C "$_gp_repo" checkout -q main
    git -C "$_gp_repo" merge -q --ff-only merged-deletable
    # unmerged: a commit absent from main (must survive the merge gate)
    git -C "$_gp_repo" checkout -q -b unmerged
    echo u > "$_gp_repo/u"; git -C "$_gp_repo" add u
    git -C "$_gp_repo" -c commit.gpgsign=false commit -qm u
    # gone-unmerged: unmerged AND its upstream was deleted — [gone] is NOT a merge
    # signal, so it must survive too.
    git init -q --bare "$_gp_bare"
    git -C "$_gp_repo" remote add origin "$_gp_bare"
    git -C "$_gp_repo" checkout -q -b gone-unmerged
    echo g > "$_gp_repo/g"; git -C "$_gp_repo" add g
    git -C "$_gp_repo" -c commit.gpgsign=false commit -qm g
    git -C "$_gp_repo" push -q -u origin gone-unmerged
    git -C "$_gp_repo" push -q origin --delete gone-unmerged
    git -C "$_gp_repo" update-ref -d refs/remotes/origin/gone-unmerged
    git -C "$_gp_repo" checkout -q main
    # Sanity: the fixture must really show [gone] and really hold a worktree, or
    # those two exclusion cases are vacuous.
    check "git-prune-merged fixture: [gone] branch is unmerged and a worktree holds one" \
        bash -c 'git -C "$1" branch -vv | grep -q "\[origin/gone-unmerged: gone\]" &&
            ! git -C "$1" branch --merged main --format="%(refname:short)" | grep -qxF gone-unmerged &&
            git -C "$1" worktree list --porcelain | grep -qxF "branch refs/heads/merged-worktree"' \
        _ "$_gp_repo"
    check "git-prune-merged: dry-run lists only the deletable merge, deletes nothing" \
        bash -c 'out=$(cd "$1" && fish -N -c "source $2; git-prune-merged" 2>&1)
            grep -qxF "  merged-deletable" <<<"$out" || exit 1
            ! grep -qxF "  main" <<<"$out" || exit 1
            ! grep -qxF "  merged-worktree" <<<"$out" || exit 1
            ! grep -qxF "  unmerged" <<<"$out" || exit 1
            ! grep -qxF "  gone-unmerged" <<<"$out" || exit 1
            git -C "$1" show-ref --verify --quiet refs/heads/merged-deletable' \
        _ "$_gp_repo" "$_GIT_PRUNE"
    check "git-prune-merged: --apply deletes exactly the deletable merge" \
        bash -c 'cd "$1" && fish -N -c "source $2; git-prune-merged --apply" >/dev/null 2>&1
            ! git -C "$1" show-ref --verify --quiet refs/heads/merged-deletable || exit 1
            git -C "$1" show-ref --verify --quiet refs/heads/merged-worktree || exit 1
            git -C "$1" show-ref --verify --quiet refs/heads/unmerged || exit 1
            git -C "$1" show-ref --verify --quiet refs/heads/gone-unmerged || exit 1
            git -C "$1" show-ref --verify --quiet refs/heads/main' \
        _ "$_gp_repo" "$_GIT_PRUNE"
    rm -rf "$_gp"
    else
        _defer 3
    fi
fi

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

# ── pi-use: variant switcher between upstream pi and pi-bolt ────────────────
# Both variants share ~/.pi/agent; pi-use owns only the ~/.local/bin/pi symlink
# plus a state file, so a flip changes which binary runs, nothing else.  Checks
# split the way pi's own do: repo-level always, host-level only where the thing
# is installed (CI runners have neither).
_PI_USE="$DOTFILES/base/pi/.local/bin/pi-use"
check "pi-use: exists in the pi stow package" test -f "$_PI_USE"
check "pi-use: is executable" test -x "$_PI_USE"
check_not "mise: pi-bolt is NOT mise-managed (its own installer + pi-use own it)" \
    '^pi-bolt[[:space:]]*=' "$MISE_CFG"

# pi-bolt is the DEFAULT `pi` binary and shares ~/.pi/agent, so it needs no
# provisioning of its own — only its install and the variant convergence, both
# asserted. Bootstrap must never move its version (that is agents-update's
# deliberate, eval-paired act), and must never fight a recorded choice.
check "bootstrap: ensure_bolt defined" \
    grep -q '^ensure_bolt()' "$DOTFILES/bootstrap.sh"
check "bootstrap: ensure_variant_default defined" \
    grep -q '^ensure_variant_default()' "$DOTFILES/bootstrap.sh"
check_has "bootstrap: pi-bolt install is non-interactive (PIBOLT_YES)" \
    'PIBOLT_YES=1' "$DOTFILES/bootstrap.sh"
check_has "bootstrap: the variant default is converged after ensure_pi" \
    '^[[:space:]]*ensure_variant_default$' "$DOTFILES/bootstrap.sh"
# Installing bolt AFTER the flip would leave the host on upstream until the next
# run, and flipping before it exists makes pi-use bolt fail.
check_has "bootstrap: pi-bolt is installed after ensure_pi, before the flip" \
    '^[[:space:]]*ensure_bolt$' "$DOTFILES/bootstrap.sh"
# The fork-default's one long-term risk is silent drift from upstream pi; the
# status line must keep saying where bolt sits, so the mechanism is asserted.
check_has "pi-use: status reports bolt's pi alignment against upstream" \
    "aligned: pi" "$_PI_USE"
check_has "bootstrap: a recorded variant choice is recognised by link shape" \
    '_pi_use_link_matches' "$DOTFILES/bootstrap.sh"
check_has "pi-use: accepts the installer layout (release tree beside the binary)" \
    'examples/extensions/subagent' "$_PI_USE"
check_has "pi-use: bolt flip names the non-interactive installer" \
    'PIBOLT_YES=1' "$_PI_USE"
# The OTHER Go rewrite that ships a binary called `pig` is tombstoned, not
# provisioned. Its name is assembled here on purpose: the repo-wide scan two
# checks down looks for the JOINED name, so an unsplit mention in this file would
# make check.sh its own allowlist entry and the scan would prove nothing.
# (Naming rule: docs/AGENT-SAFETY.md §7. "pig" here means MichaelKinsy/PiG.)
_ZORO_IMPOSTOR='Zoro''Space'
check_not "pig: never provisioned (no mise entry names the other Go rewrite)" \
    "${_ZORO_IMPOSTOR}/pig" "$MISE_CFG"
check_not "pig: bootstrap never installs the other Go rewrite" \
    "${_ZORO_IMPOSTOR}/pig" "$DOTFILES/bootstrap.sh"
# Repo-wide, so a NEW file cannot start depending on it: every mention has to sit
# in one of the files that must name it — the naming rule (spec + gotchas), the
# README section that tells a reader which project is meant, the one refusal that
# quotes the discriminator, and TODO's open work. Anywhere else is a review event.
check_has "naming: the spec carries the naming rule (impostor named once, by name)" \
    "$_ZORO_IMPOSTOR" "$DOTFILES/docs/AGENT-SAFETY.md"
check_has "naming: gotchas carry the one-command discriminator" \
    "$_ZORO_IMPOSTOR" "$DOTFILES/docs/GOTCHAS.md"
_ZORO_ALLOW="TODO.md base/pi/README.md base/pi/.local/bin/pi-use docs/AGENT-SAFETY.md docs/GOTCHAS.md"
_zoro_hits=$(git -C "$DOTFILES" grep -l -- "$_ZORO_IMPOSTOR" 2>/dev/null || true)
_zoro_extra=$(printf '%s\n' "$_zoro_hits" | grep -vxF "$(printf '%s\n' $_ZORO_ALLOW)" || true)
[[ -n "$_zoro_extra" ]] && printf '      %s\n' "$_zoro_extra"
check "pig: every mention of the impostor is inside the allowlist" \
    test -z "$_zoro_extra"
check_has "bootstrap: ensure_pi honours a deliberate pi-bolt flip" \
    'pi-variant' "$DOTFILES/bootstrap.sh"

# pi-use's pig target is the RESOLVED binary path, not the same-dir name: pig
# comes from `go install`/mise (usually not ~/.local/bin), so a relative `pig`
# target dangles and leaves `pi` unrunnable. Both halves of that contract are
# asserted, plus a behavioural flip under a throwaway HOME below.
check_has "pi-use: pig links the resolved binary, not the same-dir name" \
    'flip_link "\$pig_bin"' "$_PI_USE"
check_has "pi-use: the link is swapped by rename, so it is never absent mid-flip" \
    'mv -f "\$link_tmp"' "$_PI_USE"
check_has "pi-use: recognises an absolute pig link target as the pig variant" \
    'is_pig_target' "$_PI_USE"

if command -v pi-use >/dev/null 2>&1; then
    check "pi-use: stowed live at ~/.local/bin/pi-use" \
        bash -c '[[ "$(readlink -f "$HOME/.local/bin/pi-use")" == "$1" ]]' _ "$_PI_USE"

    # Behavioural, on a fake binary — PiG's two preconditions ARE the contract.
    # The link must carry the RESOLVED path (a mise/ubi install lives outside
    # ~/.local/bin, so a relative `pig` target dangles and leaves `pi` unrunnable),
    # stay runnable, and read back as pig through `current`. $0 is the script path,
    # passed by check().
    check_full "pi-use: pig flip links the resolved binary (PIG_USE_PI_DIRS=1)" bash -c '
        tmp=$(cd "$(mktemp -d)" && pwd -P); trap "rm -rf \"$tmp\"" EXIT
        mkdir -p "$tmp/.local/bin" "$tmp/.pi/agent/bin" "$tmp/toolbin"
        printf "#!/bin/sh\nexit 0\n" >"$tmp/.pi/agent/bin/pi"
        printf "#!/bin/sh\necho 0.7.0+1.5.0\n" >"$tmp/toolbin/pig"
        chmod +x "$tmp/.pi/agent/bin/pi" "$tmp/toolbin/pig"
        ln -s ../../.pi/agent/bin/pi "$tmp/.local/bin/pi"
        HOME="$tmp" PATH="$tmp/toolbin:$PATH" PIG_USE_PI_DIRS=1 "$0" pig >/dev/null 2>&1 || exit 1
        [ "$(readlink "$tmp/.local/bin/pi")" = "$tmp/toolbin/pig" ] || exit 2
        [ -x "$tmp/.local/bin/pi" ] || exit 3
        [ "$(cat "$tmp/.pi/agent/pi-variant" 2>/dev/null)" = pig ] || exit 4
        [ "$(HOME="$tmp" PATH="$tmp/toolbin:$PATH" "$0" current)" = pig ] || exit 5
    ' "$_PI_USE"

    # A plain-file pig cannot catch a resolution regression: the reported path and the
    # resolved path are identical, so linking the shim and linking the binary look the
    # same. A shimmed pig is what mise actually produces, and the failure it hides is
    # real — the link then only works while the owning shims dir is on PATH.
    check_full "pi-use: pig flip resolves a symlinked shim (link never records the shim)" bash -c '
        tmp=$(cd "$(mktemp -d)" && pwd -P); trap "rm -rf \"$tmp\"" EXIT
        mkdir -p "$tmp/.local/bin" "$tmp/.pi/agent/bin" "$tmp/shim" "$tmp/real/0.7.0/bin"
        printf "#!/bin/sh\nexit 0\n" >"$tmp/.pi/agent/bin/pi"
        printf "#!/bin/sh\necho 0.7.0+1.5.0\n" >"$tmp/real/0.7.0/bin/pig"
        chmod +x "$tmp/.pi/agent/bin/pi" "$tmp/real/0.7.0/bin/pig"
        ln -s ../../.pi/agent/bin/pi "$tmp/.local/bin/pi"
        ln -s ../real/0.7.0/bin/pig "$tmp/shim/pig"
        HOME="$tmp" PATH="$tmp/shim:$PATH" PIG_USE_PI_DIRS=1 "$0" pig >/dev/null 2>&1 || exit 1
        [ "$(readlink "$tmp/.local/bin/pi")" = "$tmp/real/0.7.0/bin/pig" ] || exit 2
        [ -x "$tmp/.local/bin/pi" ] || exit 3
        [ "$(PATH=/usr/bin:/bin "$tmp/.local/bin/pi" 2>/dev/null)" = 0.7.0+1.5.0 ] || exit 4
        [ "$(HOME="$tmp" PATH=/usr/bin:/bin "$0" current)" = pig ] || exit 5
    ' "$_PI_USE"

    # A mise shim is not a symlink to the tool: it is the mise binary in disguise, so
    # resolving one yields `mise` and the version probe reads mise's own --version.
    # That is a CORRECT refusal wearing a broken-install costume — it once made a
    # working host look like "pi-use pig did not work". mise knows the real path, so
    # ask it before falling back to resolution.
    check_full "pi-use: pig flip asks mise for the real binary (a shim is not the tool)" bash -c '
        tmp=$(cd "$(mktemp -d)" && pwd -P); trap "rm -rf \"$tmp\"" EXIT
        mkdir -p "$tmp/.local/bin" "$tmp/.pi/agent/bin" "$tmp/real/0.7.0/bin" "$tmp/shim" "$tmp/bin"
        printf "#!/bin/sh\nexit 0\n" >"$tmp/.pi/agent/bin/pi"
        printf "#!/bin/sh\necho 0.7.0+1.5.0\n" >"$tmp/real/0.7.0/bin/pig"
        printf "#!/bin/sh\necho 2026.10.14 macos-arm64\n" >"$tmp/shim/pig"
        chmod +x "$tmp/.pi/agent/bin/pi" "$tmp/real/0.7.0/bin/pig" "$tmp/shim/pig"
        ln -s ../../.pi/agent/bin/pi "$tmp/.local/bin/pi"
        # mise answers `which pig` with the install path, exactly as the real one does.
        printf "#!/bin/sh\n[ \"\$1\" = which ] && { echo \"$tmp/real/0.7.0/bin/pig\"; exit 0; }; exit 1\n" >"$tmp/bin/mise"
        chmod +x "$tmp/bin/mise"
        out=$(HOME="$tmp" PATH="$tmp/bin:$tmp/shim:$PATH" PIG_USE_PI_DIRS=1 "$0" pig 2>&1) || exit 2
        [ "$(readlink "$tmp/.local/bin/pi")" = "$tmp/real/0.7.0/bin/pig" ] || exit 3
        printf "%s" "$out" | grep -q "0.7.0+1.5.0" || exit 4
    ' "$_PI_USE"

    # Shared mode is the only supported posture and `1` is the only enabling value:
    # anything else silently swaps ~/.pi/agent for ~/.pig/agent (settings, trust,
    # every extension) with no error. Every refusal must leave the link AND the state
    # file untouched — a half-done flip is worse than a refused one. `env -u` matters:
    # the live shell exports the variable, so an inherited value would mask this.
    check_full "pi-use: pig flip refused unless PIG_USE_PI_DIRS is exactly 1 (link+state untouched)" bash -c '
        tmp=$(mktemp -d); trap "rm -rf \"$tmp\"" EXIT
        mkdir -p "$tmp/.local/bin" "$tmp/.pi/agent/bin" "$tmp/toolbin"
        printf "#!/bin/sh\nexit 0\n" >"$tmp/.pi/agent/bin/pi"
        printf "#!/bin/sh\necho 0.7.0+1.5.0\n" >"$tmp/toolbin/pig"
        chmod +x "$tmp/.pi/agent/bin/pi" "$tmp/toolbin/pig"
        ln -s ../../.pi/agent/bin/pi "$tmp/.local/bin/pi"
        for v in UNSET 0 true; do
            if [ "$v" = UNSET ]; then
                HOME="$tmp" PATH="$tmp/toolbin:$PATH" env -u PIG_USE_PI_DIRS "$0" pig >/dev/null 2>&1 && exit 1
            else
                HOME="$tmp" PATH="$tmp/toolbin:$PATH" PIG_USE_PI_DIRS="$v" "$0" pig >/dev/null 2>&1 && exit 1
            fi
            [ "$(readlink "$tmp/.local/bin/pi")" = "../../.pi/agent/bin/pi" ] || exit 2
            [ ! -e "$tmp/.pi/agent/pi-variant" ] || exit 3
        done
    ' "$_PI_USE"

    # The version string is the one discriminator a bin dir cannot fake: PiG prints
    # <pig>+<pi>, the impostor a bare 1.5.0. Flipping that in drops infra-safety and
    # the rest of the extension stack silently, so the refusal must name it.
    check_full "pi-use: pig flip refuses a bare version (names the impostor, nothing changed)" bash -c '
        tmp=$(mktemp -d); trap "rm -rf \"$tmp\"" EXIT
        mkdir -p "$tmp/.local/bin" "$tmp/.pi/agent/bin" "$tmp/toolbin"
        printf "#!/bin/sh\nexit 0\n" >"$tmp/.pi/agent/bin/pi"
        printf "#!/bin/sh\necho 1.5.0\n" >"$tmp/toolbin/pig"
        chmod +x "$tmp/.pi/agent/bin/pi" "$tmp/toolbin/pig"
        ln -s ../../.pi/agent/bin/pi "$tmp/.local/bin/pi"
        out=$(HOME="$tmp" PATH="$tmp/toolbin:$PATH" PIG_USE_PI_DIRS=1 "$0" pig 2>&1) && exit 1
        printf "%s" "$out" | grep -q "Zoro""Space" || exit 2
        [ "$(readlink "$tmp/.local/bin/pi")" = "../../.pi/agent/bin/pi" ] || exit 3
        [ ! -e "$tmp/.pi/agent/pi-variant" ] || exit 4
    ' "$_PI_USE"

    check "pi-use: no drift between the recorded variant and the pi symlink" \
        pi-use status

    # Under an active pi-bolt default, the pieces that make the flip real are not
    # optional: a half-wired host must fail here, not at pi's first start.
    if [ "$(cat "${HOME}/.pi/agent/pi-variant" 2>/dev/null)" = bolt ]; then
        check "bolt: the pi link is a runnable pi-bolt" \
            bash -c '[[ -x "$(readlink -f "$HOME/.local/bin/pi")" ]]'
        check "bolt: upstream pi stays installed as the rollback path" \
            test -f "$HOME/.pi/agent/install/managed-install.json"
        check "bolt: the release tree ships version-matched subagent examples" \
            bash -c '[[ -f "$(dirname "$(readlink -f "$HOME/.local/bin/pi-bolt")")/examples/extensions/subagent/index.ts" ]]'
        check "bolt: the extension stack still loads (shared ~/.pi/agent)" \
            test -f "$HOME/.pi/agent/settings.json"
        check "bolt: status reports its pi alignment (drift visibility)" \
            bash -c 'pi-use status | grep -q "^aligned: pi"'
    fi

    # PiG hosts Pi's own TS extensions in a Node child process, so the flip is safe
    # only in shared mode: the gate is asserted as the CONDITION pi-use tests, not as
    # prose about it. This replaces the old "no extension system" warning, which
    # described the impostor rather than the binary this target installs.
    check_has "pi-use: the pig flip is gated on the exact value PIG_USE_PI_DIRS=1" \
        'PIG_USE_PI_DIRS:-}"[[:space:]]*=[[:space:]]*1' "$_PI_USE"

    # Host probe for the binary itself: the two facts every assertion above assumes.
    # A bare `1.5.0` here means an impostor is on PATH, and `~/.pig/agent` means some
    # session ran unshared — both are the failure this whole section guards.
    if command -v pig >/dev/null 2>&1; then
        check "pig: PIG_VERSION_FORMAT=pi prints a bare pi version (base pin readable)" \
            bash -c 'env PIG_VERSION_FORMAT=pi pig --version 2>/dev/null | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+$"'
        check "pig: plain --version is <pig>+<pi> (this is PiG, not the impostor)" \
            bash -c 'env -u PIG_VERSION_FORMAT pig --version 2>/dev/null | grep -q "+"'
        check "pig: no unshared state dir (~/.pig/agent means shared mode never ran)" \
            test ! -e "$HOME/.pig/agent"
        # The export is the shell's half of shared mode, so it is read through a real
        # login shell rather than by grepping the file the fish section already pins.
        if [ -e "$HOME/.config/fish/conf.d/pig.fish" ]; then
            check "pig: a login fish exports PIG_USE_PI_DIRS=1 (shared mode is live)" \
                bash -c 'env -i HOME="$HOME" PATH="$PATH" TERM=dumb fish -l -c "test \"\$PIG_USE_PI_DIRS\" = 1"'
        else
            _skip "pig: a login fish exports PIG_USE_PI_DIRS=1 (shared mode is live)" \
                "conf.d/pig.fish is not stowed yet (stow --no-folding -d base -t ~ fish)"
        fi
    else
        _skip "pig: shared-mode host probes (version shapes, no ~/.pig/agent, shell export)" \
            "pig is not installed on this host (mise install; the pin is ubi:MichaelKinsy/PiG)"
    fi

    if [ -e "$HOME/.local/bin/pi-bolt" ]; then
        # Two supported shapes: the curl installer's release tree (which is what
        # `pi update --self` rewrites in place and what ships version-matched
        # examples) and npm's launcher, which needs its sibling install.sh.
        check "pi-bolt: recognised install shape (release tree or npm launcher)" \
            bash -c 'r=$(readlink -f "$HOME/.local/bin/pi-bolt"); [[ -x "$r" ]] && [[ -f "${r%/*}/../install.sh" || -f "${r%/*}/examples/extensions/subagent/index.ts" ]]'
    fi
fi

# ── pi trust: the deliberate entries, in the ONE store every variant reads ──
# A trust store is a flat {"/abs/path": true|false}; resolution walks UP from
# the cwd to the nearest key, so a PREFIX key covers every repo beneath it —
# present and future — which is why the checkout roots are stored as roots and
# never enumerated per project. There is exactly ONE store: under
# PIG_USE_PI_DIRS=1 PiG reads ~/.pi/agent/trust.json, the same file pi and pi-bolt
# read, so a second store would only describe the unshared mode `pi-use` refuses to
# flip into. Assert on it when it exists — CI and a fresh host have none.
_PI_TRUST_ENTRIES="personal lelapa"   # prefix roots only — see README → Project trust
_PI_TRUST_STORE="$HOME/.pi/agent/trust.json"
if [ -e "$_PI_TRUST_STORE" ]; then
    check "pi trust: the shared store trusts the source roots (pi|pi-bolt|PiG)" \
        python3 -c '
import json, os, sys
store, home, entries = sys.argv[1], sys.argv[2], sys.argv[3].split()
want = {os.path.realpath(os.path.join(home, "src", e)) for e in entries}
# Keys are compared RAW on purpose: PiG and pi match a CANONICALISED cwd against
# the stored key, so a non-canonical key (e.g. written through a symlinked $HOME)
# trusts nothing — realpath-ing the keys here would hide exactly that drift.
with open(store) as fh:
    have = {k for k, v in json.load(fh).items() if v is True}
sys.exit(0 if want <= have else 1)
' "$_PI_TRUST_STORE" "$HOME" "$_PI_TRUST_ENTRIES"
else
    _skip "pi trust: the shared store trusts the source roots (pi|pi-bolt|PiG)" \
        "no ~/.pi/agent/trust.json (fresh host / pi state not initialised)"
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

# ── Paseo ──────────────────────────────────────────────────────────────────
# Paseo Desktop bundles its own daemon and CLI: it installs both itself and
# updates them itself, so nothing here provisions or stows either. What this repo
# owns is the daemon's config.json — the file the daemon reads its intent from
# (listen address, allowed Host headers, provider toggles, agent profiles) and
# writes back only on an explicit edit (`paseo daemon config set`, the app's
# Settings panes), which is why it is stowed rather than templated.
section "Paseo (host-local daemon config)"

# hosts/mbpm3, not base: daemon.listen is the machine's Tailscale name and
# daemon.hostnames repeats it, so one shared copy would make a second host's
# daemon fail to bind. The macOS host layer is stowed wholesale (bootstrap), so
# adding this package needed no stow-list edit.
_PASEO_CFG="$DOTFILES/hosts/mbpm3/paseo/.paseo/config.json"

check "paseo: daemon config ships in hosts/mbpm3 (tailnet listen is per-machine)" \
    test -f "$_PASEO_CFG"

check "paseo: daemon config is valid JSON" \
    python3 -m json.tool "$_PASEO_CFG"

# Every other file in ~/.paseo is runtime state (agents/, projects/, schedules/,
# worktrees/, logs, pid, credential keys). Tracking one of those would commit a
# machine's live sessions; the intent lives in config.json alone.
check "paseo: only config.json is tracked from ~/.paseo" \
    bash -c 'test "$(git -C "$1" ls-files hosts/mbpm3/paseo)" = "hosts/mbpm3/paseo/.paseo/config.json"' \
    _ "$DOTFILES"

# `paseo daemon set-password` writes a bcrypt hash into 
# daemon.auth.password in THIS file (docs: configuration.md, "Password
# authentication"), and the file is tracked: a password set on the host would be
# one `git add` away from the repo in the clear. The structured check names the
# path to unset; the second pass is the backstop for the hash landing anywhere
# else in the file (a nested key, a renamed field).
check "paseo: no daemon password hash is committed" \
    python3 -c '
import json, re, sys
d = json.load(open(sys.argv[1]))
auth = (d.get("daemon") or {}).get("auth") or {}
if auth.get("password"):
    sys.exit("daemon.auth.password is committed — remove it before tracking this file")
blob = open(sys.argv[1]).read()
if re.search(r"\$2[aby]\$[0-9]{2}\$", blob):
    sys.exit("a bcrypt hash appears in the file outside daemon.auth.password")
' "$_PASEO_CFG"

# A daemon bound to the tailnet name answers the phone's Host header from
# daemon.hostnames; if the two drift the app connects and then gets refused.
check "paseo: daemon.hostnames covers the daemon.listen host" \
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1])).get("daemon", {})
listen = d.get("listen") or ""
host = listen.rsplit(":", 1)[0] if listen else ""
if not host:
    sys.exit("daemon.listen is unset — nothing to bind")
if host in ("127.0.0.1", "0.0.0.0", "localhost", "::1"):
    sys.exit(0)
if host not in (d.get("hostnames") or []):
    sys.exit("daemon.listen host %r is missing from daemon.hostnames %r" % (host, d.get("hostnames")))
' "$_PASEO_CFG"

# The daemon starts under launchd with no direnv hook, so both enabled harnesses launch
# through paseo-agent-env, which hands an agent the .envrc scope of its SOURCE repo and
# no wider (docs/AGENT-SAFETY.md §5, 2026-11-21). A provider without it either fails MCP
# auth or, under a blanket `direnv exec`, leaks the work credentials into ~/dotfiles.
_PAE="$DOTFILES/base/paseo/bin/paseo-agent-env"
check "paseo: pi and claude both launch through ~/bin/paseo-agent-env" \
    python3 -c '
import json, sys
p = json.load(open(sys.argv[1]))["agents"]["providers"]
for name in ("pi", "claude"):
    cmd = p.get(name, {}).get("command") or []
    if cmd[:1] != ["/Users/sett/bin/paseo-agent-env"] or len(cmd) < 2:
        sys.exit("%s.command does not start with the launcher: %r" % (name, cmd))
' "$_PASEO_CFG"
check "paseo-agent-env: is executable (Paseo execs it directly)" test -x "$_PAE"
# No .sh suffix, so the shellcheck pass over every script never sees it.
check "paseo-agent-env: parses (sh -n)" sh -n "$_PAE"
check_full "paseo-agent-env: shellcheck clean as POSIX sh" shellcheck -S warning -s sh "$_PAE"

# Behaviour, on a sandboxed HOME with a stub direnv first on PATH (the real one needs an
# allow, and the mise shim breaks under a fake HOME — GOTCHAS). The stub sources the
# directory's .envrc and execs, which is all the launcher asks of direnv. The layout is
# the real one in miniature: a work repo under a workspace .envrc, a linked worktree of
# it under .paseo/worktrees with no .envrc above it, a personal repo with none, and a
# $HOME/.envrc that must never count. Physical paths, or macOS's /var alias hides HOME.
_pae_d=$(cd "$(mktemp -d)" && pwd -P)
_pae_h="$_pae_d/home"
_pae_bin="$_pae_d/stub"
mkdir -p "$_pae_bin" "$_pae_h/work/repo" "$_pae_h/personal/repo" "$_pae_h/.paseo/worktrees/x"
printf '#!/bin/sh\n[ "$1" = exec ] || exit 64\nd=$2; shift 2\nset -a; . "$d/.envrc"; set +a\nexec "$@"\n' \
    > "$_pae_bin/direnv"
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done\n' > "$_pae_bin/fakebin"
chmod +x "$_pae_bin/direnv" "$_pae_bin/fakebin"
printf 'export PAE_MARK=work\n' > "$_pae_h/work/.envrc"
printf 'export PAE_MARK=home\n' > "$_pae_h/.envrc"
HOME="$_pae_h" git init -q -b main "$_pae_h/work/repo"
HOME="$_pae_h" git -C "$_pae_h/work/repo" -c commit.gpgsign=false -c user.email=c@example.invalid \
    -c user.name=c commit -q --allow-empty -m init
HOME="$_pae_h" git -C "$_pae_h/work/repo" worktree add -q "$_pae_h/.paseo/worktrees/x/slug" -b slug
HOME="$_pae_h" git init -q -b main "$_pae_h/personal/repo"
# $1 = directory the agent starts in, $2 = HOME, $3 = stub dir, $4 = launcher, $5 = value
# PAE_MARK must have ("" = absent), $6 = optional PASEO_AGENT_CWD.
_pae_mark='out=$(cd "$1" && env -i HOME="$2" PATH="$3:/usr/bin:/bin" ${6:+PASEO_AGENT_CWD="$6"} \
        "$4" sh -c "printf %s \"\${PAE_MARK-}\"") && test "$out" = "$5"'
check "paseo-agent-env: a Paseo worktree of a work repo gets the work .envrc" \
    bash -c "$_pae_mark" _ "$_pae_h/.paseo/worktrees/x/slug" "$_pae_h" "$_pae_bin" "$_PAE" work
check "paseo-agent-env: a repo with no .envrc below \$HOME gets nothing (\$HOME's own ignored)" \
    bash -c "$_pae_mark" _ "$_pae_h/personal/repo" "$_pae_h" "$_pae_bin" "$_PAE" ""
check "paseo-agent-env: PASEO_AGENT_CWD, not the daemon's cwd, decides the scope" \
    bash -c "$_pae_mark" _ "$_pae_h/personal/repo" "$_pae_h" "$_pae_bin" "$_PAE" work \
    "$_pae_h/.paseo/worktrees/x/slug"
check "paseo-agent-env: argv reaches the harness intact" \
    bash -c 'out=$(cd "$1" && env -i HOME="$2" PATH="$3:/usr/bin:/bin" "$4" "$3/fakebin" --version "a b") &&
        test "$out" = "$(printf -- "--version\na b")"' \
    _ "$_pae_h/.paseo/worktrees/x/slug" "$_pae_h" "$_pae_bin" "$_PAE"
rm -rf "$_pae_d"

# Paseo installs its agent skills into ~/.agents/skills/ and records what it owns
# in .paseo-managed-files.json beside them, then rewrites those files on update;
# ~/.local/bin/paseo is a symlink into the app bundle, made by the app. Both are
# the app's own install: a repo-owned link would fight the updater or dangle
# after an app move. Stated as repo intent (the index), so it holds in CI too.
check "paseo: the app's own install (skills, ~/.local/bin/paseo) is not tracked" \
    bash -c '! git -C "$1" ls-files | grep -qE "(\.agents/skills/paseo|\.local/bin/paseo)"' \
    _ "$DOTFILES"

# The daemon writes config.json in place (measured 2026-11-17 on a throwaway
# --home: `paseo daemon config set` kept the symlink and wrote through it), which
# is what makes stowing it safe. A future release writing via tempfile+rename
# would replace the link with a plain file and the repo copy would go stale
# without an error — catch that here. Absent on CI, hence the skip.
if [[ -e "$HOME/.paseo/config.json" || -L "$HOME/.paseo/config.json" ]]; then
    check "paseo: live ~/.paseo/config.json is still the stow link (no rename-write)" \
        bash -c '[ -L "$1" ] && python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1" | grep -qF "$2"' \
        _ "$HOME/.paseo/config.json" "$DOTFILES/hosts/mbpm3/paseo/.paseo/config.json"
else
    _skip "paseo: live ~/.paseo/config.json is still the stow link (no rename-write)" \
        "no live paseo home on this host (CI)"
fi

# bootstrap's stow preflight removes a plain file that conflicts with a stow
# package. Paseo creates config.json on first launch, so on a host that ran the
# app before this package landed, that `rm` would drop the live settings (listen,
# profiles, possibly a password hash). _ensure_paseo_config moves it aside first.
check_has "bootstrap: _ensure_paseo_config defined" \
    '^_ensure_paseo_config\(\)' "$DOTFILES/bootstrap.sh"
check "bootstrap: _ensure_paseo_config runs before _stow_preflight, not just the stow" \
    bash -c 'c=$(grep -n "^ *_ensure_paseo_config$" "$1" | tail -1 | cut -d: -f1)
        p=$(grep -n "^ *_stow_preflight$" "$1" | tail -1 | cut -d: -f1)
        test -n "$c" && test -n "$p" && test "$c" -lt "$p"' _ "$DOTFILES/bootstrap.sh"
# End-to-end for the ordering above: a plain ~/.paseo/config.json is a FATAL
# conflict for _stow_preflight, so a run WITHOUT the backup aborts and one with
# it proceeds. Both halves are asserted, or the test would pass on a preflight
# that simply got loosened.
if command -v stow >/dev/null 2>&1; then
    _PASEO_E2E=$(mktemp -d)
    check_full "bootstrap: paseo backup unblocks the fatal plain-file preflight" bash -c '
        d="$2"
        mkdir -p "$d/dotfiles/hosts/h/paseo/.paseo" "$d/.paseo"
        printf "%s" "{\"daemon\": {\"listen\": \"tracked\"}}" > "$d/dotfiles/hosts/h/paseo/.paseo/config.json"
        sed "/^main \"\$@\"$/d" "$1" > "$d/bootstrap.sh" || exit 1
        # 1. without the backup: preflight aborts on the plain file (rc != 0)
        cp "$d/dotfiles/hosts/h/paseo/.paseo/config.json" "$d/.paseo/config.json"
        printf "%s" "{\"daemon\": {\"listen\": \"live\"}}" > "$d/.paseo/config.json"
        if env HOME="$d" DOTFILES="$d/dotfiles" bash -c "source \"$d/bootstrap.sh\"; host=h; platform=macos; _stow_preflight" >/dev/null 2>&1; then
            echo "preflight passed with a conflicting plain file — the test is not measuring the abort"; exit 1
        fi
        # 2. with the backup: same fixture, preflight green
        if ! env HOME="$d" DOTFILES="$d/dotfiles" bash -c "source \"$d/bootstrap.sh\"; host=h; platform=macos; _ensure_paseo_config; _stow_preflight" >/dev/null 2>&1; then
            echo "backup did not clear the fatal conflict"; exit 1
        fi
        ls "$d"/.paseo/config.json.pre-dotfiles-* >/dev/null 2>&1 || { echo "live bytes were not kept"; exit 1; }
        exit 0' _ "$DOTFILES/bootstrap.sh" "$_PASEO_E2E"
    rm -rf "$_PASEO_E2E"
else
    _skip "bootstrap: paseo backup unblocks the fatal plain-file preflight" "stow not installed"
fi
# Functional, through the real function: differing live bytes survive in the
# backup path, and an identical copy is left for stow to replace without a
# backup (no clutter per bootstrap).
check_full "bootstrap: _ensure_paseo_config backs up a differing live config" \
    bash -c 'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT
        mkdir -p "$d/dotfiles/hosts/h/paseo/.paseo" "$d/.paseo"
        printf "%s" "{\"daemon\": {\"listen\": \"tracked\"}}" > "$d/dotfiles/hosts/h/paseo/.paseo/config.json"
        printf "%s" "{\"daemon\": {\"listen\": \"live\"}}" > "$d/.paseo/config.json"
        sed "/^main \"\$@\"$/d" "$1" > "$d/bootstrap.sh" || exit 1
        env HOME="$d" DOTFILES="$d/dotfiles" bash -c "source \"$d/bootstrap.sh\"; host=h; _ensure_paseo_config" >/dev/null 2>&1 || exit 1
        test ! -e "$d/.paseo/config.json" || exit 1
        b=$(ls "$d"/.paseo/config.json.pre-dotfiles-* 2>/dev/null | head -1)
        test -n "$b" || exit 1
        grep -q "live" "$b" || exit 1
        printf "%s" "{\"daemon\": {\"listen\": \"tracked\"}}" > "$d/.paseo/config.json"
        env HOME="$d" DOTFILES="$d/dotfiles" bash -c "source \"$d/bootstrap.sh\"; host=h; _ensure_paseo_config" >/dev/null 2>&1 || exit 1
        # Identical bytes are still a FATAL preflight conflict, so they must be
        # dropped too — nothing is lost (the tracked copy holds them) and no
        # second backup appears.
        test ! -e "$d/.paseo/config.json" || exit 1
        test "$(ls "$d"/.paseo/config.json.pre-dotfiles-* | wc -l)" -eq 1 || exit 1
        # …and the preflight the migration serves is now green for this host.
        env HOME="$d" DOTFILES="$d/dotfiles" bash -c "source \"$d/bootstrap.sh\"; host=h; platform=macos; _stow_preflight" >/dev/null 2>&1 || exit 1
        exit 0' _ "$DOTFILES/bootstrap.sh"

# Claude Code reports turn/session events to the daemon through its hooks, but
# only inside a Paseo terminal: PASEO_TERMINAL_ID is set there and nowhere else,
# so an ungated (or inverted-gate) hook would run `paseo hooks` in every terminal
# on every host. Matching the whole command, not a substring: `hooks claude Stop`
# is a prefix of StopFailure, and a comment could satisfy a substring test.
check "claude: paseo hooks cover five events and are gated on PASEO_TERMINAL_ID" \
    python3 -c '
import json, sys
hooks = (json.load(open(sys.argv[1])).get("hooks") or {})
want = ["UserPromptSubmit", "Stop", "StopFailure", "SessionEnd", "Notification"]
missing = [e for e in want if e not in hooks]
if missing:
    sys.exit("no paseo hook for: " + ", ".join(missing))
for event in want:
    expected = ("if [ -n \"$PASEO_TERMINAL_ID\" ]; then \"${PASEO_HOOK_CLI:-paseo}\" "
                "hooks claude " + event + "; fi")
    cmds = [h.get("command", "") for m in hooks[event] for h in (m.get("hooks") or [])]
    if expected not in cmds:
        sys.exit(event + ": expected hook command not found, got: " + repr(cmds))
' "$DOTFILES/base/claude/.claude/settings.json"

# ── Agent safety layers ─────────────────────────────────────────────────────
# docs/AGENT-SAFETY.md is the contract: each layer names the file that makes it real,
# and this section asserts those files exist and behave. A layer whose file never
# landed is red here, never believed — a spec that describes intent as fact is how
# the next session inherits a hole it thinks is covered.
section "Agent safety layers (docs/AGENT-SAFETY.md)"

_SAFETY_SPEC="$DOTFILES/docs/AGENT-SAFETY.md"
_EXT="$DOTFILES/base/pi/.pi/agent/extensions"

check "safety: the spec exists (every layer row cites a file in it)" \
    test -f "$_SAFETY_SPEC"
check_has "safety: the spec carries its dated verification log" \
    'Verification log \(2026-11-16\)' "$_SAFETY_SPEC"
# A settled question must stay settled in the SPEC, not just in the plan: the pwt
# forwarding question is closed in §5 (creds per command, docs/WT.md), and the section
# survives as the record of decisions rather than being deleted with the argument.
check_has "safety: the spec keeps its settled-questions section" \
    'Settled policy questions' "$_SAFETY_SPEC"
check_not "safety: no pwt forwarding claim survives in the spec" \
    'pwt forwards|__pwt_forward_env' "$_SAFETY_SPEC"
check_has "safety: the spec records the measured bypass (probeA.sh, residual 5)" \
    'probeA\.sh' "$_SAFETY_SPEC"
# Session-scoped working notes are host-local scratch (.pi/plans is gitignored, never
# committed) and must never be cited by the contract: a stale plan reads as ground
# truth to the next session, which is what the capture tiers exist to prevent.
check_not "safety: the contract cites no host-local plan (.pi/plans is scratch)" \
    '\.pi/plans' "$_SAFETY_SPEC"

# L2 — the infra write gate. ONE shell-tool declaration (lib/shell-tools.ts) feeds
# both gates, so a session whose shell arrives as `bash` (any harness without
# pi-hypa's replace mode) is gated too; a hook that hard-codes hypa_shell leaves it
# decorative there, and a second copy drifts silently.
check_has "safety: L2 declares SHELL_TOOLS once, in lib/shell-tools.ts" \
    '^export const SHELL_TOOLS' "$_EXT/lib/shell-tools.ts"
check_has "safety: the gate re-exports the shared declaration" \
    'SHELL_TOOLS' "$_EXT/lib/mutation-guard.ts"
_sh_only=$(grep -rlE 'isToolCallEventType\([[:space:]]*["'"'"']hypa_shell' \
    "$_EXT"/*.ts "$_EXT"/optional/*.ts "$_EXT"/optional/modes/*.ts 2>/dev/null || true)
[[ -n "$_sh_only" ]] && printf '      %s\n' "$_sh_only"
check "safety: L2 gates no tool name only (no hook hard-codes hypa_shell)" \
    test -z "$_sh_only"
# The optional axis is one DIRECTORY, because that is how a downstream appliance
# strips it: `rm -rf extensions/optional`. A root-level extension importing from
# optional/ would leave that appliance holding a file whose import it deleted — the
# startup-crash class, in a form no appliance-side list can see.
_opt_imported=$(grep -rnE "(from|import)[[:space:]]*\(?[[:space:]]*['\"]\./optional/" \
    "$_EXT"/*.ts 2>/dev/null || true)
[[ -n "$_opt_imported" ]] && printf '      %s\n' "$_opt_imported"
check "pi extensions: nothing in the required core imports from optional/" \
    test -z "$_opt_imported"
# 4e: a script body is inspected, not its filename — `sh /tmp/probeA.sh` was the
# measured bypass, and an unreadable/oversize body classifies as unknown (blocked).
check_has "safety: L2 inspects shell script bodies (expandScripts, 4e)" \
    '^export { expandScripts }' "$_EXT/lib/classify.ts"
check_has "safety: the script walk itself lives in script-expand.ts (4e)" \
    '^export function expandScripts' "$_EXT/lib/script-expand.ts"

# L2's second half — the secret-path gate (owner decision 2026-11-16, spec §2.1a,
# §5). Probe E measured the gap: L3 allows `hypa_read` of secrets/env.fish, because
# the file is git-crypt'd rather than `.env`-shaped. The gate is on the FILE tools
# only; the shell stays with the classifier and with L3, because this repo's own
# scanners run `grep secrets/leak-patterns`. Three checks: the wiring names every
# file tool and no shell tool, the pure suite runs with a pinned count, and the
# decision is driven end to end (deny the credential store, allow the corpus).
check "safety: L2 wires the secret-path gate to the FILE tools only" bash -c '
    ext="$1/optional/infra-safety.ts"; mod="$1/lib/secret-paths.ts"
    grep -q "secretPathBlock(event.toolName" "$ext" || exit 1
    for t in read hypa_read grep hypa_grep find hypa_find edit write; do
        grep -qE "^  \"$t\",\$" "$mod" || exit 1
    done
    ! grep -qE "^  \"(bash|hypa_shell)\",\$" "$mod"
' _ "$_EXT"
if [[ "$_CAN_STRIP_TS" -eq 1 ]]; then
    check_full "safety: L2 secret-path suite passes $_TS_PIN_SECRET_PATHS/$_TS_PIN_SECRET_PATHS (count pinned)" \
        _ts_suite_count secret-paths.test.ts "$_TS_PIN_SECRET_PATHS"
    check_full "safety: L2 denies hypa_read of secrets/env.fish, allows secrets/leak-patterns" \
        node --experimental-strip-types --input-type=module -e '
const { secretPathBlock } = await import(process.argv[1]);
const cwd = process.argv[2];
const deny = secretPathBlock("hypa_read", { path: "secrets/env.fish" }, cwd);
const allow = secretPathBlock("hypa_read", { path: "secrets/leak-patterns" }, cwd);
const shell = secretPathBlock("hypa_shell", { command: "cat secrets/env.fish" }, cwd);
const sane = deny && deny.block === true && /^secret-path: blocked/.test(deny.reason);
process.exit(sane && allow === null && shell === null ? 0 : 1);
' "$_EXT/lib/secret-paths.ts" "$DOTFILES"
else
    _skip "safety: L2 secret-path suite passes $_TS_PIN_SECRET_PATHS/$_TS_PIN_SECRET_PATHS (count pinned)" \
        "node build lacks --experimental-strip-types TS support (need v23+ or TS-compiled build)"
    _skip "safety: L2 denies hypa_read of secrets/env.fish, allows secrets/leak-patterns" \
        "node build lacks --experimental-strip-types TS support (need v23+ or TS-compiled build)"
fi

# L4 — the publish guard. The message names the rule or the variable and never the
# matched value; that is the whole point, because the value is already in context.
check_has "safety: L4 block template names the rule, never the matched value" \
    'publish-guard: blocked — outgoing text matches' "$_EXT/lib/publish-scan.ts"
check_has "safety: L4 asks the scanner to redact its own report" \
    '"--redact"' "$_EXT/publish-guard.ts"
check_has "safety: L4 hooks the web tools (their arguments leave the host)" \
    'fetch_content' "$_EXT/publish-guard.ts"
# The identifier corpus (secrets/leak-patterns) belongs to .githooks/pre-commit and
# the leak-patterns scan above: it names internal hosts and customer identifiers, not
# credential shapes, so L4 must not quietly become a second owner of it.
check_not "safety: L4 does not borrow the pre-commit identifier corpus" \
    'leak-patterns' "$_EXT/publish-guard.ts"
check_not "safety: L4's pure core does not borrow the identifier corpus either" \
    'leak-patterns' "$_EXT/lib/publish-scan.ts"

# L3 — cc-safety-net. Its config and rules are STOWED from base/cc-safety-net so an
# edit is a reviewable diff, and its rulebooks are pinned to a commit: a floating
# `#main` means the rules that run are whatever upstream pushed that morning.
_CCSN_BASE="$DOTFILES/base/cc-safety-net/.cc-safety-net"
_CCSN_RULE="$_CCSN_BASE/rules/rule.json"
_CCSN_PROJ="$DOTFILES/.cc-safety-net/rules/rule.json"
_CCSN_BOOK="$DOTFILES/.cc-safety-net/rules/dotfiles-rules/rulebook.json"
check "safety: L3 user config ships in base/cc-safety-net (stowed, reviewable)" \
    test -f "$_CCSN_RULE"
# Probe B: shell tools are declarable, so no adapter is needed to put pi-hypa's shell
# tool under L3 — but only the DECLARED ones are covered, which is why it is asserted.
check_has "safety: L3 declares the hypa shell tool (probe B)" \
    '"hypa_shell"' "$_CCSN_RULE"
check_not "safety: L3 pins its rulebooks (no floating #main/#master/#HEAD)" \
    '#\((main|master|HEAD)\)' "$_CCSN_RULE"
check_not "safety: L3 project rules pin their rulebook too" \
    '#\((main|master|HEAD)\)' "$_CCSN_PROJ"
check "safety: every L3 rulebook ref is pinned to a 40-hex commit" \
    python3 -c "
import json, re, sys
bad = []
for path in sys.argv[1:]:
    try:
        refs = json.load(open(path)).get('rules', [])
    except Exception as exc:
        bad.append('%s: %s' % (path, exc))
        continue
    for ref in refs:
        if '#' in ref and not re.search(r'#[0-9a-f]{40}/[a-z0-9-]+\$', ref):
            bad.append('%s: %s' % (path, ref))
if bad:
    sys.stderr.write('\n'.join(bad))
sys.exit(1 if bad else 0)
" "$_CCSN_RULE" "$_CCSN_PROJ"
# Step 3's project rules (the L1 --no-verify bypass, forced pushes, forced adds) are
# only useful if they are shown to block, and only trustworthy if they also show what
# they let through — a rulebook of deny-everything passes half of this fixture.
check "safety: the project rulebook carries fixtures for every rule (+ an allow case)" \
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
rules = {r.get('name') for r in d.get('rules', [])}
tests = d.get('tests', [])
blocked = {t.get('rule') for t in tests if t.get('expect') == 'blocked'}
allows = [t for t in tests if t.get('expect') == 'allowed']
missing = rules - blocked
if missing:
    sys.stderr.write('no blocked fixture for: %s\n' % ', '.join(sorted(missing)))
sys.exit(0 if rules and not missing and allows else 1)
" "$_CCSN_BOOK"

# Host half of L3, skipped where the layer is not installed/stowed (CI, a fresh host).
# The package is declared in the settings template, so a host that dropped it has L3
# gone silently — the one failure mode the spec names for this layer.
_CCSN_LIVE="$HOME/.cc-safety-net"
_CCSN_PIN=$(python3 -c "
import json, sys
for p in json.load(open(sys.argv[1])).get('packages', []):
    if p.startswith('npm:cc-safety-net'):
        print(p); break
" "$DOTFILES/base/pi/.pi/agent/settings.desired.json")
# Run whenever ANY of the two files is already a stow link: that is the difference
# between "not installed on this host" (skip, with the reason) and a half-stowed
# tree, where the second file is cc-safety-net's own copy and rule edits stop being
# visible to git — a drift this check must catch, not skip.
if [ -L "$_CCSN_LIVE/rules/rule.json" ] || [ -L "$_CCSN_LIVE/policy.json" ]; then
    check "safety: the live L3 config is the stow link into base/cc-safety-net" \
        bash -c 'for f in policy.json rules/rule.json; do
            l="$1/$f"
            [ -L "$l" ] || exit 1
            [ "$(readlink -f "$l")" = "$2/$f" ] || exit 1
        done' _ "$_CCSN_LIVE" "$_CCSN_BASE"
    # Probe C: a declared `npm:` package is auto-installed into <agent-dir>/npm. The
    # pin is only real if the INSTALLED copy matches it, or L3 runs older rules than
    # the file this repo asserts.
    _CCSN_INSTALLED=""
    for _cand in "$HOME"/.pi/agent/npm/node_modules/cc-safety-net "$HOME"/.pi/agent/npm/cc-safety-net; do
        [ -f "$_cand/package.json" ] && { _CCSN_INSTALLED="$_cand"; break; }
    done
    if [ -n "$_CCSN_INSTALLED" ]; then
        check "safety: the installed cc-safety-net matches the pinned version" \
            python3 -c "
import json, re, sys
pin = re.fullmatch(r'npm:cc-safety-net@([0-9]+\.[0-9]+\.[0-9]+)', sys.argv[1])
installed = json.load(open(sys.argv[2])).get('version')
sys.exit(0 if pin and installed == pin.group(1) else 1)
" "$_CCSN_PIN" "$_CCSN_INSTALLED/package.json"
        # Probe A, as a library call rather than a session: the layer must deny the
        # one destructive verb it is trusted for and must not deny an ordinary read
        # (deny-by-default would be a different product, and unusable).
        check_full "safety: L3 library denies 'git reset --hard' and allows 'ls'" \
            node --input-type=module -e '
import { pathToFileURL } from "node:url";
const { checkCommand } = await import(pathToFileURL(`${process.argv[1]}/dist/api.js`).href);
const deny = checkCommand({ command: "git reset --hard", cwd: process.env.HOME });
const allow = checkCommand({ command: "ls", cwd: process.env.HOME });
process.exit(deny.kind === "deny" && allow.kind === "allow" ? 0 : 1);
' "$_CCSN_INSTALLED"
    else
        _skip "safety: the installed cc-safety-net matches the pinned version" \
            "no installed copy under ~/.pi/agent/npm (pi install it from the settings package)"
        _skip "safety: L3 library denies 'git reset --hard' and allows 'ls'" \
            "cc-safety-net is not installed under ~/.pi/agent/npm"
    fi
else
    _skip "safety: the live L3 config is the stow link into base/cc-safety-net" \
        "base/cc-safety-net is not stowed on this host (stow --restow --no-folding -d base -t ~ cc-safety-net)"
    _skip "safety: the installed cc-safety-net matches the pinned version" \
        "L3 config is not stowed, so the layer is not installed on this host"
    _skip "safety: L3 library denies 'git reset --hard' and allows 'ls'" \
        "L3 config is not stowed, so the layer is not installed on this host"
fi

# L0 — no credential is exported at shell startup. Two halves, because either alone is
# a prose pin: (a) the static guarantee that `source secrets/env.fish` never comes back
# into a STARTUP file, and (b) a behavioural probe that a clean login shell exports
# none of the names that file defines (printed names only, never values).
# L0's other half, now that a workstream window is an ordinary shell: nothing may forward
# the values into a tmux server or a window any more (the old spawn path used `tmux -e`),
# and `creds` must stay one-shot — a child fish that EXECs, so nothing lands in the calling
# shell. Together these are what makes the settled §5 answer quotable without an asterisk.
check_not "safety: nothing forwards a credential into a tmux server or window" \
    'secrets/env\.fish|tmux -e ' "$DOTFILES/base/tmux/.config/tmux/tmux.conf"
check_has "safety: creds execs in a child fish (one-shot, never an export)" \
    'command fish --no-config -c.*exec \$argv' "$DOTFILES/base/fish/.config/fish/config.fish"
check_not "safety: L0 — config.fish never sources the secrets file at startup" \
    '^[[:space:]]*[^#]*source[[:space:]]+[^ ]*secrets/env\.fish' "$FISH_CFG"
_l0_confd=$(grep -lE '^[[:space:]]*[^#]*source[[:space:]]+[^ ]*secrets/env\.fish' \
    "$DOTFILES"/base/fish/.config/fish/conf.d/*.fish 2>/dev/null || true)
[[ -n "$_l0_confd" ]] && printf '      %s\n' "$_l0_confd"
check "safety: L0 — no conf.d file sources the secrets file at startup" \
    test -z "$_l0_confd"
_L0_SECRETS="$DOTFILES/secrets/env.fish"
if [ ! -r "$_L0_SECRETS" ] || head -c 16 "$_L0_SECRETS" 2>/dev/null | grep -aq GITCRYPT; then
    _skip "safety: L0 — a clean login shell exports no secret name" \
        "secrets/env.fish is locked/absent (git-crypt unlock runs the behavioural probe)"
elif ! command -v fish >/dev/null 2>&1; then
    _skip "safety: L0 — a clean login shell exports no secret name" \
        "fish is not installed on this host"
else
    check_full "safety: L0 — a clean login shell exports no secret name" bash -c '
        names=$(sed -nE "s/^[[:space:]]*set[[:space:]]+-[A-Za-z]*x[A-Za-z]*[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/p" "$1" | sort -u)
        [ -n "$names" ] || exit 1
        exported=$(env -i HOME="$HOME" PATH="$PATH" TERM=dumb fish -l -c env 2>/dev/null \
            | sed -n "s/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p")
        leak=$(printf "%s\n" "$exported" | grep -xF "$names" || true)
        [ -z "$leak" ] || { printf "      exported at startup: %s\n" "$leak" >&2; exit 1; }
    ' _ "$_L0_SECRETS"
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
# PiG has no `update` subcommand, so mise is its only updater and `--bump` is what
# rewrites the pinned line in the (tracked, stowed) config.toml — the version move
# arrives as a reviewable diff instead of floating with every `mise upgrade`. The
# old refusal (`test "$variant" = pig`) is gone because it is no longer true of the
# target: under PiG `pi` IS the harness mise just bumped.
check_has "agents-update: bumps the PiG pin through mise (--bump, the reviewable diff)" \
    "mise upgrade --bump 'ubi:MichaelKinsy/PiG'" "$_AGENTS_UPDATE"
check_not "agents-update: the old 'refuses to self-update under pig' branch is gone" \
    'test "\$variant" = pig' "$_AGENTS_UPDATE"
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

# Measured 2026-11-05: the provider answered 429/overloaded for 12 of 30 arm-B runs, and
# the summarizer counted each as an ordinary "0 edits" run — trivial read as 6/10 when
# all six answered runs made their one edit. A run that never got an answer is an
# infrastructure failure, not a prompt result: excluded, and shouted about.
#
# A behavioural self-test, not a grep pin: a pin on the word "auto_retry_end" still
# passes if both functions are deleted and the comment above them survives. The fixtures
# cover three classes — retries exhausted, an empty answer with no retry event (the hard
# error the first cut of this classifier missed), and a valid run — and require the
# valid run's tool call to be counted exactly once.
check_full "pi-smoke: classifier self-test (retries exhausted, empty answer, valid run)" \
    env PI_SMOKE_SELFTEST=1 bash "$DOTFILES/pi-smoke.sh"

# --append-system-prompt REPLACES discovery of APPEND_SYSTEM.md (pi's resource-loader),
# so the prompt stamp above names a file the model never saw unless the override is
# stamped too. Without this, a flagged run's numbers are unattributable.
check_has "pi-smoke: stamps the override prompt when one is pinned" \
    'override     ' "$DOTFILES/pi-smoke.sh"
check_has "pi-smoke: a missing override file warns instead of vanishing" \
    'none of the prompt stamps above describe what ran' "$DOTFILES/pi-smoke.sh"



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

# ══════════════════════════════════════════════════════════════════════════════
# FIX PINS — one per finding from the 2026-11-20 repo audit. Each pin fails if
# the fix is reverted, and names the failure it prevents.
# ══════════════════════════════════════════════════════════════════════════════
section "Audit fixes (2026-11-20)"

# A fresh Mac runs `bash bootstrap.sh` with /bin/bash 3.2, where a bash-4
# associative array is a parse-time crash halfway through a privileged run.
check_not "bootstrap.sh: no bash-4 associative arrays (fresh macOS has bash 3.2)" \
    '^[[:space:]]*declare -A' "$DOTFILES/bootstrap.sh"
# A key path the user named but that cannot be read must be an error, not a
# silent fall-through to the interactive prompt.
check_has "bootstrap.sh: a set-but-unreadable DOTFILES_KEY is reported" \
    'DOTFILES_KEY is set but is not a readable file' "$DOTFILES/bootstrap.sh"
# /etc/wsl.conf is root-owned and hand-tuned on real machines: keep the old one.
check_has "bootstrap.sh: /etc/wsl.conf is backed up before it is replaced" \
    'wsl.conf.bak-' "$DOTFILES/bootstrap.sh"

# The Windows-side SSH dir is shared with the Windows user; never wipe it.
check_has "up.sh: rescues a hand-edited Windows ssh config.d before the copy" \
    'config.d.bak-' "$DOTFILES/os/wsl/up.sh"
# A renamed/imported WSL distro must not leave a dead default terminal profile.
check_has "up.sh: VSCodium profile distro comes from WSL_DISTRO_NAME" \
    'WSL_DISTRO_NAME' "$DOTFILES/os/wsl/up.sh"
check_has "vscodium settings: WSL terminal profile is a placeholder, not a distro" \
    '__WSL_DISTRO__' "$DOTFILES/os/wsl/windows/vscodium/settings.json"

# `^\+` alone matched the '+++ b/<path>' header, so a clean file whose NAME held a
# stem was blocked. Start the scan at the first hunk header instead.
check "pre-commit: leak scan starts at the hunk header (no filename hit)" \
    grep -qF "sed -n '/^@@/,\$p'" "$DOTFILES/.githooks/pre-commit"

# A crashed agent leaves its socket file behind; ssh-agent then refuses to bind
# and the dead path gets exported, silently breaking every ssh.
check_has "ssh-agent.fish: a proven-dead socket is removed before starting" \
    'rm -f "\$AUTH_SOCK"' "$DOTFILES/base/fish/.config/fish/conf.d/ssh-agent.fish"
# Without a controlling terminal `tty` prints 'not a tty', and that became GPG_TTY.
check_has "config.fish: GPG_TTY is only set when a terminal is attached" \
    'if test -t 0' "$DOTFILES/base/fish/.config/fish/config.fish"
check "config.fish: GPG_TTY is not exported unconditionally" bash -c \
    '! grep -qE "^set -gx GPG_TTY" "$1"' _ "$DOTFILES/base/fish/.config/fish/config.fish"

# `sed -i ''` is BSD-only: on GNU sed the digest rewrite never ran, yet the
# function still printed 'digests updated'.
check_not "tt.fish: no BSD-only in-place sed (GNU sed silently no-ops)" \
    "sed -i ''" "$DOTFILES/base/fish/.config/fish/functions/tt.fish"
# Pin the REWRITE, not any `string replace` (the digest *extraction* already used
# one before this fix, so matching that would pass on a revert). grep -F: the
# pattern is fish source, not a regex.
check "tt.fish: digests are rewritten fish-natively, not by sed" \
    grep -qF "string replace -r '(TT_BACKEND_IMAGE=" "$DOTFILES/base/fish/.config/fish/functions/tt.fish"
# $frontend_port was defined nowhere, so `tt up` always printed 13000.
check_not "tt.fish: no undefined frontend_port variable" \
    'set -l fp \$frontend_port' "$DOTFILES/base/fish/.config/fish/functions/tt.fish"
# A failed compose printed a green tick.
check_has "tt.fish: a failed compose call is reported, not celebrated" \
    'if not __tt_compose' "$DOTFILES/base/fish/.config/fish/functions/tt.fish"

# fish treats an empty value as set, so an early failed lookup poisoned the cache.
check_has "wsl.fish: the Windows path cache only stores a non-empty result" \
    'test -n "\$_localappdata"' "$DOTFILES/base/fish/.config/fish/conf.d/wsl.fish"
check_has "wsl.fish: the WSL guard does not fork uname on every shell" \
    'set -q WSL_DISTRO_NAME' "$DOTFILES/base/fish/.config/fish/conf.d/wsl.fish"

# pipefail + a grep that matched nothing killed the whole status script; the
# substring filter also hid real addresses like 192.168.127.5.
check_not "tmux-status: the address filter is not a substring match" \
    "grep -vE '127|172'" "$DOTFILES/base/tmux/bin/tmux-status"
# The runtime smoke check cannot see the Linux branch on a Mac; pin the guard that
# makes an all-filtered list a blank segment instead of a failure.
check "tmux-status: an all-filtered address list does not fail the segment" \
    grep -qF '|| true' "$DOTFILES/base/tmux/bin/tmux-status"
# Dead binding: C-a last-window replaced it three lines later.
check_not "tmux.conf: no dead C-a send-prefix binding" \
    '^bind C-a send-prefix$' "$DOTFILES/base/tmux/.config/tmux/tmux.conf"
check_has "tmux.conf: send-prefix is still reachable on its own key" \
    'a send-prefix' "$DOTFILES/base/tmux/.config/tmux/tmux.conf"
# The comment pointed at a binding that no longer does that job.
check_not "sesh.toml: the comment does not claim C-o does zoxide filtering" \
    'zoxide query -l --base-dir' "$DOTFILES/base/sesh/.config/sesh/sesh.toml"

# SUMMARY
# =============================================================================
printf '\n%b%s%b\n' "$(_c "$BLD")" \
    "── Results ────────────────────────────────" "$(_c "$RST")"

_profile_report

printf '  %b✓%b %-3d passed\n'  "$C_GRN" "$C_RST" "$PASS"
printf '  %b✗%b %-3d failed\n'  "$C_RED" "$C_RST" "$FAIL"
[[ $SKIP -gt 0 ]] && \
printf '  %b○%b %-3d skipped\n' "$C_YLW" "$C_RST" "$SKIP"
# Deferred is its OWN bucket, never folded into passed or skipped-with-needs: the
# count says how much of the suite this run did not execute.
[[ $DEFERRED -gt 0 ]] && \
printf '  %b○%b %-3d behavioural checks deferred (CHECK_FULL=1 or CI runs them)\n' \
    "$C_YLW" "$C_RST" "$DEFERRED"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    printf '\n%bFailed tests:%b\n' "$(_c "$BLD")" "$(_c "$RST")"
    for f in "${FAILED[@]}"; do
        printf '  %b✗%b %s\n' "$(_c "$RED")" "$(_c "$RST")" "$f"
    done
fi

echo ""
[[ $FAIL -eq 0 ]]
