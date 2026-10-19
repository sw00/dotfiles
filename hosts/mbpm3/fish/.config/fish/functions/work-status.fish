# work-status — is the work toolchain authenticated right now?
#
# Probes only: no side effects, no writes, no state of its own. It discovers WHAT
# to probe from the tools' own config, so no cluster, server, team, account or
# domain identifier appears in this file. That is the rule — identifiers live in
# machine-local tool config, never in this repo. See check.sh's leak scan.
#
# Why a live call and not a cached expiry: the AWS refresh token re-mints itself
# silently every hour (observed TTL exactly 60 min), so its expiry says nothing
# about whether a browser is needed. Only the org's Identity Center sign-in
# session governs that, and it is not stored anywhere readable. A live call is
# the only true answer, and it costs one round trip.
#
# Run this in a real terminal: the pi `infra-safety` extension blocks these verbs
# from an agent shell.

function __work_aws_sso_profile --description 'First ~/.aws/config profile using SSO'
    awk '
        /^\[profile / { p = $0; sub(/^\[profile[ \t]+/, "", p); sub(/\][ \t]*$/, "", p) }
        /^sso_session[ \t]*=/ { if (p != "") { print p; exit } }
    ' "$HOME/.aws/config" 2>/dev/null
end

function __work_fly_targets --description 'Fly targets that are not local-only (from ~/.flyrc)'
    # Target names are the 2-space-indented keys under `targets:`; their fields
    # (api, team, token) sit deeper. Only that exact indent matches, so the
    # nested keys stay out.
    #
    # Targets pointing at localhost are skipped: they are a local dev Concourse,
    # never a work target, and trying to `login` to one would fail on every run
    # and leave a permanent false alarm in `work-status`.
    awk '
        function flush() {
            if (name != "" && api != "" && api !~ /localhost|127[.]0[.]0[.]1/)
                print name
        }
        /^targets:/          { intgt = 1; next }
        intgt && /^[^ \t]/     { intgt = 0 }
        intgt && /^  [^ \t]/   { flush(); name = $0; sub(/^[ \t]+/, "", name); sub(/:.*$/, "", name); api = ""; next }
        intgt && /^[ \t]+api:/ { api = $2 }
        END                  { flush() }
    ' "$HOME/.flyrc" 2>/dev/null
end

function __work_exec_contexts --description 'Count kubeconfig users authenticating via an exec plugin'
    kubectl config view -o jsonpath='{range .users[*]}{.user.exec.command}{"\n"}{end}' 2>/dev/null | grep -c .
end

function work-status --description 'Report work toolchain authentication state'
    set -l ok 0
    set -l bad 0

    # aws
    set -l prof (__work_aws_sso_profile)
    if test -z "$prof"
        printf '%-8s · no SSO profile in ~/.aws/config\n' aws
    else if aws sts get-caller-identity --profile $prof --query Account --output text >/dev/null 2>&1
        printf '%-8s ✓ session live\n' aws
        set ok (math $ok + 1)
    else
        printf '%-8s ✗ needs login\n' aws
        set bad (math $bad + 1)
    end

    # az — the Azure side of the estate, and what any kubelogin-backed contexts
    # below authenticate against. `account show` is the live probe, same
    # reasoning as aws: it re-mints silently from the stored refresh token, so
    # the cached expiry says nothing about whether a browser is needed.
    # The subscription name is printed, not stored. The rule is that identifiers
    # never enter the repo — not that they never surface in your own terminal,
    # which is also how the fly targets below work.
    # What this answers is "is the CLI authenticated", which is the part that can
    # live here. Which subscription work commands should target is deliberately
    # left out: encoding it would mean carrying the very identifier this file
    # must not have, and it is a machine-local choice anyway — so this reports
    # the default, which is what a bare `az` command would hit.
    if not command -q az
        printf '%-8s · not installed\n' az
    else
        set -l sub (az account show --query name -o tsv 2>/dev/null)
        if test -n "$sub"
            printf '%-8s ✓ authenticated (%s)\n' az $sub
            set ok (math $ok + 1)
        else
            printf '%-8s ✗ needs login\n' az
            set bad (math $bad + 1)
        end
    end

    # k8s — exec-plugin contexts mint a token per request off whichever cloud
    # session they use (EKS off aws, ARO/AKS off az), so there is nothing to
    # authenticate here; if those are live, so is this.
    printf '%-8s · %s exec-plugin context(s), rides the cloud sessions\n' k8s (__work_exec_contexts)

    # argocd
    if not command -q argocd
        printf '%-8s · not installed\n' argocd
    else if argocd account get-user-info >/dev/null 2>&1
        printf '%-8s ✓ authenticated\n' argocd
        set ok (math $ok + 1)
    else
        printf '%-8s ✗ needs login\n' argocd
        set bad (math $bad + 1)
    end

    # fly — `fly status` is documented as "Login status".
    if not command -q fly
        printf '%-8s · not installed\n' fly
    else
        for t in (__work_fly_targets)
            if fly -t $t status >/dev/null 2>&1
                printf '%-8s ✓ target %s\n' fly $t
                set ok (math $ok + 1)
            else
                printf '%-8s ✗ target %s needs login\n' fly $t
                set bad (math $bad + 1)
            end
        end
    end

    echo
    if test $bad -gt 0
        echo "$bad need attention — run: work-login"
        return 1
    end
    echo 'ready for work'
end
