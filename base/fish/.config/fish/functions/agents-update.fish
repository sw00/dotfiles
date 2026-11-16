# agents-update — bring PiG, pi and Claude Code to latest, then flag the
# follow-up work that needs a human.
#
# pi and Claude Code own themselves and are deliberately absent from the mise
# config (see AGENTS.md). PiG is the one harness mise owns — pinned on purpose,
# because it has no self-updater of its own. Bootstrap installs all three but
# never upgrades them: an upgrade swaps the harness under the prompts this repo
# ships, so it has to be paired with the smoke eval that only a human can judge.
# This is the entry point for that pairing — run it, read the tail, do what it
# says.
#
# MANUAL ONLY, like pi-prune-sessions. Nothing schedules this: an unattended
# upgrade is exactly what bootstrap is forbidden from doing.
#
# Usage: agents-update
function agents-update --description 'Update PiG, pi and Claude Code, then flag the eval work that follows'
    # `pi` may currently BE pig (pi-use pig). PiG is a Go rewrite with no `update`
    # subcommand, so mise is its only updater: it is pinned in base/mise's
    # config.toml and `mise upgrade --bump` is the one thing allowed to move that
    # pin. This function IS that pairing — it bumps, then judges the eval below.
    #
    # That is NOT a reason to skip upstream pi, which is what the old pig branch
    # did: upstream pi is the rollback binary (`pi-use pi`) and the release tree
    # whose examples the subagent extension loads from, so leaving it behind ages
    # the one path a rollback lands on. It is updated through its own launcher
    # (~/.pi/agent/bin/pi) instead, and the two versions are reported separately —
    # one number cannot describe two binaries.
    #
    # What the judgement reads is the pi version baked INTO PiG, not PiG's own
    # wrapper version: `PIG_VERSION_FORMAT=pi` prints just that half
    # (`0.7.0+1.5.0` → `1.5.0`), so the same regex below reads the harness version
    # whichever binary `pi` points at. Upstream pi ignores the variable, so it is
    # correct there too.
    #
    # pi-bolt needs no guard: installed by its curl installer, `pi update --self`
    # replaces ~/.pi-bolt in place, so the version compare below is truthful.
    set -l pi_is_pig 0
    if command -v pi-use >/dev/null 2>&1
        if test (pi-use current 2>/dev/null) = pig
            set pi_is_pig 1
        end
    end

    set -l before (env PIG_VERSION_FORMAT=pi pi --version 2>/dev/null | string match -r '^[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    set -l pig_after
    # The managed install records what upstream `pi update --self` last landed on,
    # and it is readable even while `pi` resolves to PiG. Declared at function
    # scope on purpose: fish scopes `set -l` to the enclosing block, so declaring
    # these inside the `if` below would lose them before the report at the tail.
    set -l upstream_before
    set -l upstream_after
    if test $pi_is_pig = 1
        set upstream_before (cat ~/.pi/agent/install/current-version 2>/dev/null)
    end

    echo '── PiG'
    if not command -v pig >/dev/null 2>&1
        echo 'agents-update: pig is not installed — skipping it (mise owns it: `mise install`)' >&2
    else
        set -l pig_before (env PIG_VERSION_FORMAT=pi pig --version 2>/dev/null | string match -r '^[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        # `--bump` rewrites the pinned line in the stowed config.toml, i.e. in the
        # repo. That rewrite is the point: the version move arrives as a reviewable
        # diff instead of floating forward with every `mise upgrade`.
        if not mise upgrade --bump 'ubi:MichaelKinsy/PiG'
            echo 'agents-update: mise upgrade --bump ubi:MichaelKinsy/PiG failed (offline?) — staying on the installed pin' >&2
        end
        set pig_after (env PIG_VERSION_FORMAT=pi pig --version 2>/dev/null | string match -r '^[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        test -n "$pig_before"; or set pig_before unknown
        test -n "$pig_after"; or set pig_after unknown
        echo "pig pi-part $pig_before -> $pig_after"
    end

    echo '── pi'
    if test $pi_is_pig = 1
        # `pi` is a symlink to PiG right now, so `pi update --self` would land on a
        # Go binary with no update subcommand. Reach upstream through its own
        # launcher rather than skipping it: the managed install is what a rollback
        # (`pi-use pi`) runs and where the subagent example comes from.
        if not test -x ~/.pi/agent/bin/pi
            echo "agents-update: upstream launcher ~/.pi/agent/bin/pi is missing — run pi.dev's install.sh (the active `pi` is PiG, bumped by mise above)" >&2
        else if not ~/.pi/agent/bin/pi update --self
            echo 'agents-update: upstream pi update failed (offline?) — staying on the installed version' >&2
        end
        set upstream_after (cat ~/.pi/agent/install/current-version 2>/dev/null)
        test -n "$upstream_before"; or set upstream_before unknown
        test -n "$upstream_after"; or set upstream_after unknown
        echo "upstream pi $upstream_before -> $upstream_after (the active `pi` is PiG, bumped above)"
    else if not pi update --self
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

    set -l current (env PIG_VERSION_FORMAT=pi pi --version 2>/dev/null | string match -r '^[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    test -n "$before"; or set before unknown
    echo
    # Informational, never a verdict: PiG's embedded pi and the installed upstream
    # pi drift freely — PiG lags a release and still shares ~/.pi/agent — so this
    # is the number to quote in a report, not a gate.
    set -l pi_installed (cat ~/.pi/agent/install/current-version 2>/dev/null)
    test -n "$pi_installed"; or set pi_installed unknown
    if test -n "$pig_after"
        echo "aligned: pig pi-part $pig_after · ~/.pi/agent/install/current-version $pi_installed"
    end
    if test -z "$current"
        echo 'agents-update: pi is not on PATH — cannot report the harness version' >&2
        return 1
    end
    # Nothing to re-vendor: the subagent extension resolves pi's own example from
    # the active release when it loads, so it is version-matched by construction.
    #
    # TWO binaries can move on a pig host, so they are judged separately: while
    # `pi` points at PiG, `before`/`current` describe PiG's pi part and upstream
    # travelled through its own launcher. Either move is a new harness under the
    # prompts this repo ships (and on the pig side a new subagent-example source),
    # so either one owes the same eval — but the report names which binary moved
    # instead of spending one version number on both.
    set -l moved
    if test "$before" != "$current"
        set -a moved "pi $before -> $current"
    end
    if test $pi_is_pig = 1; and test "$upstream_before" != "$upstream_after"
        set -a moved "upstream pi $upstream_before -> $upstream_after (rollback binary, subagent example)"
    end
    if test (count $moved) -eq 0
        echo "pi $current (unchanged) — subagent extension loads from the active release, nothing to sync."
        if test $pi_is_pig = 1
            echo "upstream pi $upstream_after (unchanged) — the rollback binary stays where it was."
        end
        echo 'No harness change, so no eval re-run is owed.'
        return 0
    end
    if test (count $moved) -eq 1
        echo "$moved[1] — the harness moved under the prompts this repo ships:"
    else
        echo 'both harnesses moved under the prompts this repo ships:'
        for line in $moved
            echo "    $line"
        end
    end
    echo '    run pi-smoke.sh and compare against docs/PROMPT-EVAL.md before trusting the numbers.'
    echo '    pi settings are host-local now (~/.pi/agent/settings.json): the template was applied above,'
    echo '    so `git status` here is about the repo, not about session drift.'
    return 1
end
