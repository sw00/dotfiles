# Autoloaded helper for work-status/build work-login.
#
# One function per file: fish autoloads a function ONLY from a file named after
# it. Defining this inside work-status.fish left it an unknown command everywhere
# except a shell where work-status had already run — and work-login's gates read
# an empty probe as "nothing to do", so the failure was silent. See
# docs/GOTCHAS.md; check.sh asserts the naming contract repo-wide.

function __work_aws_sso_profile --description 'First ~/.aws/config profile using SSO'
    awk '
        /^\[profile / { p = $0; sub(/^\[profile[ \t]+/, "", p); sub(/\][ \t]*$/, "", p) }
        /^sso_session[ \t]*=/ { if (p != "") { print p; exit } }
    ' "$HOME/.aws/config" 2>/dev/null
end
