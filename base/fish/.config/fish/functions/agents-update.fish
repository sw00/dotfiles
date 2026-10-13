# agents-update — bring pi and Claude Code to latest, then flag the follow-up
# work that needs a human.
#
# Both apps own themselves and both are deliberately absent from the mise config
# (see AGENTS.md). Bootstrap installs them but never upgrades them: an upgrade
# swaps the harness under the prompts this repo ships, so it has to be paired
# with the re-vendor and the smoke eval that only a human can judge. This is the
# entry point for that pairing — run it, read the tail, do what it says.
#
# MANUAL ONLY, like pi-prune-sessions. Nothing schedules this: an unattended
# upgrade is exactly what bootstrap is forbidden from doing.
#
# Usage: agents-update
function agents-update --description 'Update pi and Claude Code, then flag re-vendor + eval work'
    # The vendored extension carries its provenance in the header comment; that
    # stamp is the pin this function compares against the running pi.
    set -l ext "$HOME/.pi/agent/extensions/subagent/index.ts"
    set -l pinned ''
    if test -f "$ext"
        set pinned (command grep -oE '@ pi [0-9]+\.[0-9]+\.[0-9]+' "$ext" 2>/dev/null \
            | head -1 | string replace '@ pi ' '')
    end

    echo '── pi'
    if not pi update --self
        echo 'agents-update: pi update failed (offline?) — staying on the installed version' >&2
    end

    echo '── Claude Code'
    if not claude update
        echo 'agents-update: claude update failed (offline?) — staying on the installed version' >&2
    end

    set -l current (command pi --version 2>/dev/null | string match -r '^[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo
    if test -z "$current"
        echo 'agents-update: pi is not on PATH — cannot check the vendored extension pin' >&2
        return 1
    end
    if test -z "$pinned"
        echo "no vendored subagent extension at $ext — nothing to re-vendor"
    else if test "$current" = "$pinned"
        echo "subagent extension: vendored at pi $pinned, running pi $current — nothing to re-vendor"
    else
        echo "⚠ subagent extension: vendored at pi $pinned, now running pi $current — RE-VENDOR:"
        echo "    cp <pi package>/examples/extensions/subagent/{index,agents}.ts \\"
        echo "       base/pi/.pi/agent/extensions/subagent/"
        echo "    keep the two-line header and re-stamp it '@ pi $current',"
        echo "    then run pi-smoke.sh and compare against docs/PROMPT-EVAL.md"
        return 1
    end
end
