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


if [ -e /home/sett/.nix-profile/etc/profile.d/nix.sh ]; then . /home/sett/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer
