#!/usr/bin/env bash
# Tasks to (potentially )complete post-activation of home-manager that cannot be handed by HM.
# E.g. system-level stuff that requires sudo
#
# usage: sudo -E ./post-activation.sh

set -ex

BASEDIR=$(dirname $0)

PREFIX=$HOME/.nix-profile
HOSTNAME=$(cat /etc/hostname)


backup_if_exists() {
    src="$1"
    dest="$2"

    if [[ -f $dest ]]; then
        if diff -q "$src" "$dest"; then
            true # noop
        else
            backup="$(basename "$dest").$(date +%Y%m%d%H%M%S)"
            echo "+++ $dest exists with different content, making backup: $backup"
            cp $dest $(dirname $dest)/$backup_filename
        fi
    fi
}

register_xinput_config() {
    dest=/etc/X11/xorg.conf.d/50-touchpad.conf
    src=$BASEDIR/../etc/X11_xorg.conf.d/50-touchpad.$HOSTNAME.conf

    backup_if_exists $src $dest
    cp -f $src $dest
}

register_xsessions() {
    cp -f $HOME/.local/share/xsession/awesome.desktop /usr/share/xsessions/
}

register_udev_rules() {
    ln -sf $HOME/.nix-profile/etc/udev/rules.d/40-monitor-hotplug.rules /etc/xdg/autostart/
}

register_xdg_autostarts() {
    ln -s $PREFIX/etc/xdg/autostart/* /etc/xdg/autostart/
}

register_xinput_config
register_xsessions
register_udev_rules
# register_xdg_autostarts
