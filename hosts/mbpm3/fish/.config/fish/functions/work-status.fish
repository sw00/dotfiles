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

# Probe helpers live in sibling files (__work_*.fish). fish autoloads one
# function per file, so a helper defined here is invisible to any caller that
# runs before work-status in that shell — check.sh asserts the contract.

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
