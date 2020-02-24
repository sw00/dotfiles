# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# capture metadata about system for convenience
META_OS=$(uname -s | awk '{ print tolower($0) }') #linux

# locale
export LC_ALL=en_US.UTF-8

[ $META_OS = "darwin" ] && \
	META_OS="macos"

[ -n $(uname -r | grep Microsoft) ] && \
	META_OS="wsl"

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
	. "$HOME/.bashrc"
    fi
fi

# bash imports
[ -e "$HOME/.bash_imports" ] && \
    for file in $(ls -d $HOME/.bash_imports/*.sh); do
        . $file
    done

# editor
command -v nvim 2&>/dev/null && \
	export EDITOR=nvim || export EDITOR=vi

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# autojump
[[ -s $HOME/.autojump/etc/profile.d/autojump.sh ]] && source /home/sett/.autojump/etc/profile.d/autojump.sh

# passphrase prompt for gpg in terminal
export GPG_TTY=$(tty)

# timewarrior
export TIMEWARRIORDB="$HOME/Dropbox/etc/timewarrior"

# cabal
[ -e "$HOME/.cabal/bin" ] && \
    PATH="$HOME/.cabal/bin:$PATH"

# jump into fish shell
[ -e /usr/bin/fish ]  && exec /usr/bin/fish
[ -e /usr/local/bin/fish ] && exec /usr/local/bin/fish

