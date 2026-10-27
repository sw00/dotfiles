# agents-update — bring pi and Claude Code to latest, then flag the follow-up
# work that needs a human.
#
# Both apps own themselves and both are deliberately absent from the mise config
# (see AGENTS.md). Bootstrap installs them but never upgrades them: an upgrade
# swaps the harness under the prompts this repo ships, so it has to be paired
# with the smoke eval that only a human can judge. This is the
# entry point for that pairing — run it, read the tail, do what it says.
#
# MANUAL ONLY, like pi-prune-sessions. Nothing schedules this: an unattended
# upgrade is exactly what bootstrap is forbidden from doing.
#
# Usage: agents-update
function agents-update --description 'Update pi and Claude Code, then flag the eval work that follows'
    set -l before (command pi --version 2>/dev/null | string match -r '^[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    echo '── pi'
    if not pi update --self
        echo 'agents-update: pi update failed (offline?) — staying on the installed version' >&2
    end

    echo '── Claude Code'
    if not claude update
        echo 'agents-update: claude update failed (offline?) — staying on the installed version' >&2
    end

    echo '── pi settings'
    # The template is tracked in this repo, so a version move is exactly when an
    # unapplied template edit is likely to be waiting. One line when already in
    # sync ("no drift"); `pi-settings-apply -n` is the human tool for looking
    # before it writes.
    pi-settings-apply
    or echo 'agents-update: pi-settings-apply needs a look — see its output above' >&2

    set -l current (command pi --version 2>/dev/null | string match -r '^[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    test -n "$before"; or set before unknown
    echo
    if test -z "$current"
        echo 'agents-update: pi is not on PATH — cannot report the harness version' >&2
        return 1
    end
    # Nothing to re-vendor: the subagent extension resolves pi's own example from
    # the active release when it loads, so it is version-matched by construction.
    if test "$before" = "$current"
        echo "pi $current (unchanged) — subagent extension loads from the active release, nothing to sync."
        echo 'No harness change, so no eval re-run is owed.'
        return 0
    end
    echo "pi $before -> $current — the harness moved under the prompts this repo ships:"
    echo '    run pi-smoke.sh and compare against docs/PROMPT-EVAL.md before trusting the numbers.'
    echo '    pi settings are host-local now (~/.pi/agent/settings.json): the template was applied above,'
    echo '    so `git status` here is about the repo, not about session drift.'
    return 1
end
