# ssh-agent.fish — One shared agent on a fixed socket for cross-shell reuse.
#
# On macOS, launchd provides ssh-agent automatically; skip the rest.
# On Linux / WSL, start an agent on ~/.ssh/agent.sock (or adopt the
# macOS launchd agent if one is already running there).
#
# The fixed socket path means every fish shell (or tmux pane, or alacritty
# window) reuses the same agent without environment variable magic in .bashrc.
#
# This is intentionally a conf.d file so it runs early in fish startup,
# before any config.fish code that might interact with git/ssh.

# macOS: launchd already runs ssh-agent with an SSH_AUTH_SOCK in the
# inherited environment.  Nothing to do.
not set -q SSH_AUTH_SOCK; or return

# ── Agent socket path ────────────────────────────────────────────────────────
set -l SOCKET_DIR "$HOME/.ssh"
set -l AUTH_SOCK "$SOCKET_DIR/agent.sock"

mkdir -p "$SOCKET_DIR"
chmod 700 "$SOCKET_DIR"

# ── Probe the socket, if one exists ──────────────────────────────────────────
# ssh-add -l exit codes:
#   0 = agent is alive and has at least one key loaded
#   1 = agent is alive but empty (no identities)
#   2 = no agent (socket missing / not a valid agent socket)
SSH_AUTH_SOCK="$AUTH_SOCK" ssh-add -l >/dev/null 2>&1
set -l probe $status

if test $probe -ne 2
    # Socket exists and responds → adopt it (even if empty: probe == 1).
    set -gx SSH_AUTH_SOCK "$AUTH_SOCK"
    return
end

# ── Start a fresh ssh-agent ──────────────────────────────────────────────────
# Use -a to write the socket path directly, bypassing the need to eval
# ssh-agent's stdout.
ssh-agent -a "$AUTH_SOCK" -D &>/dev/null &
set -gx SSH_AUTH_SOCK "$AUTH_SOCK"
