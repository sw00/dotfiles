# Autoloaded helper for work-status/build work-login. One function per file —
# see __work_aws_sso_profile.fish for why.

function __work_exec_contexts --description 'Count kubeconfig users authenticating via an exec plugin'
    kubectl config view -o jsonpath='{range .users[*]}{.user.exec.command}{"\n"}{end}' 2>/dev/null | grep -c .
end
