# Never forward locale env vars (LANG/LC_*) via ssh.
#
# macOS/Ubuntu ship "SendEnv LANG LC_*" in /etc/ssh/ssh_config, and ssh(1)
# appends patterns from the systemwide file AFTER ~/.ssh/config, so no
# user-config SendEnv directive (or "-" negation) can remove them — see
# docs/GOTCHAS.md. Passing -F ~/.ssh/config makes ssh ignore the systemwide
# file entirely (ssh(1) man page); Include directives inside ~/.ssh/config
# still work. Caveat: scp/sftp/git exec the ssh binary directly and bypass
# this wrapper.
#
# Workbench integration: when the workbench env is active (WORKBENCH set,
# i.e. inside ~/src/lelapa/workbench via direnv), delegate to its bin/ssh
# wrapper first so the team SSH fragments (gpu-vm-*, ...) apply too. The
# wrapper builds a temp config with -F, which ignores the systemwide file
# just the same, so the locale fix below still holds in-repo.
function ssh --wraps ssh
    if set -q WORKBENCH; and test -x "$WORKBENCH/bin/ssh"
        command "$WORKBENCH/bin/ssh" $argv
    else if test -f ~/.ssh/config
        command ssh -F ~/.ssh/config $argv
    else
        command ssh $argv
    end
end