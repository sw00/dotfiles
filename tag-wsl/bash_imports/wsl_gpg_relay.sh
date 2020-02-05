#####
## Autorun for the gpg-relay bridge
##
mkdir -p $HOME/.misc
SOCAT_PID_FILE=$HOME/.misc/socat-gpg.pid

if [[ -f $SOCAT_PID_FILE ]] && kill -0 $(cat $SOCAT_PID_FILE); then
   : # already running
else
    rm -f "$HOME/.gnupg/S.gpg-agent"
    APPDATA_DIR=$(wslvar APPDATA)
    (trap "rm $SOCAT_PID_FILE" EXIT; socat UNIX-LISTEN:"$HOME/.gnupg/S.gpg-agent,fork" EXEC:'/mnt/c/tools/npiperelay/npiperelay.exe -ei -ep -s -a "$APPDATA/gnupg/S.gpg-agent"',nofork </dev/null &>/dev/null) &
    echo $! >$SOCAT_PID_FILE
fi

export SSH_AUTH_SOCK=/mnt/c/tools/wsl-ssh-pageant/ssh-agent.sock
