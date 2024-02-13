#!/usr/bin/env bash
# Tasks to (potentially )complete post-activation of home-manager that cannot be handed by HM.
# E.g. system-level stuff that requires sudo
# 
# usage: sudo -E ./post-activation.sh

set -ex

PREFIX=$HOME/.nix-profile

register_xsessions() {
    cp -f $HOME/.local/share/xsession/awesome.desktop /usr/share/xsessions/
}

register_udev_rules() {
    ln -sf $HOME/.nix-profile/etc/udev/rules.d/40-monitor-hotplug.rules /etc/xdg/autostart/
}

register_xdg_autostarts() {
    ln -s $PREFIX/etc/xdg/autostart/* /etc/xdg/autostart/
}

register_xsessions
register_udev_rules
# register_xdg_autostarts
