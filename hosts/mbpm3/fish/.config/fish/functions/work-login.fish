# work-login — idempotently authenticate the work toolchain.
#
# Checks each tool first and re-authenticates only what has actually lapsed, so
# the common case (nothing expired) is a fast no-op. Order matters: aws first,
# because the EKS contexts mint their tokens off that session.
#
# Discovered, never stored: every target this logs into is read at runtime from
# the tool's own config. No cluster, server, team, account or domain identifier
# appears in this file — that is the rule for this repo. See check.sh's leak scan.
#
# Run in a real terminal: this opens browsers, and the pi `infra-safety`
# extension blocks these verbs from an agent shell.

function work-login --description 'Authenticate the work toolchain (idempotent)'
    set -l want $argv
    test (count $want) -eq 0
    and set want aws k8s argocd fly

    set -l failed 0

    for tool in $want
        switch $tool

            case aws
                set -l prof (__work_aws_sso_profile)
                if test -z "$prof"
                    echo 'aws: no SSO profile in ~/.aws/config — nothing to do'
                else if aws sts get-caller-identity --profile $prof --query Account --output text >/dev/null 2>&1
                    echo 'aws: already live'
                else
                    echo "aws: session lapsed — logging in (browser)…"
                    aws sso login --profile $prof
                    or set failed (math $failed + 1)
                end

            case k8s
                # Existing contexts already carry an exec-plugin user block, whose
                # token is minted per request. Nothing to refresh; only a machine
                # that has never seen the clusters needs update-kubeconfig.
                set -l n (__work_exec_contexts)
                if test $n -gt 0
                    echo "k8s: $n exec-plugin context(s) — nothing to refresh"
                else
                    echo 'k8s: no exec-plugin contexts — add clusters with: aws eks update-kubeconfig --name <cluster> --region <region> --profile <profile>'
                end

            case argocd
                if not command -q argocd
                    echo 'argocd: not installed'
                else if argocd account get-user-info >/dev/null 2>&1
                    echo 'argocd: already authenticated'
                else
                    # relogin re-mints from the stored refresh token — no browser,
                    # which is the common expiry path.
                    echo 'argocd: token lapsed — relogin…'
                    argocd relogin >/dev/null 2>&1
                    if argocd account get-user-info >/dev/null 2>&1
                        echo 'argocd: refreshed'
                    else
                        # The refresh token itself has lapsed. This needs a browser
                        # per server, so hand over the exact command rather than
                        # firing several flows unattended.
                        set -l server (argocd context 2>/dev/null | awk '$1 == "*" { print $3 }')
                        test -n "$server"; or set server '<server>'
                        echo "argocd: needs a full SSO login — run:"
                        echo "  argocd login --sso $server"
                        set failed (math $failed + 1)
                    end
                end

            case fly
                if not command -q fly
                    echo 'fly: not installed'
                else
                    # `fly login` reuses the stored target's api/team from ~/.flyrc,
                    # so the target name is all it needs.
                    for t in (__work_fly_targets)
                        if fly -t $t status >/dev/null 2>&1
                            echo "fly: target $t already live"
                        else
                            echo "fly: target $t lapsed — logging in (browser)…"
                            fly -t $t login
                            or set failed (math $failed + 1)
                        end
                    end
                end

            case '*'
                echo "work-login: unknown tool '$tool' (known: aws k8s argocd fly)" >&2
                set failed (math $failed + 1)

        end
    end

    echo
    if test $failed -gt 0
        echo "$failed item(s) still need attention — run: work-status"
        return 1
    end
    echo 'all tools live'
end
