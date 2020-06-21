# locale
export LC_ALL=en_US.UTF-8 LC_TYPE=en_US.UTF-8 LANG=en_US.UTF-8

# passphrase prompt for gpg in terminal
export GPG_TTY=$(tty)

# timewarrior
export TIMEWARRIORDB="$HOME/Dropbox/etc/timewarrior"

# editor
command -v nvim 2&>/dev/null && \
	export EDITOR=nvim || export EDITOR=vi

