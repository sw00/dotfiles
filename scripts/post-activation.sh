#!/usr/bin/env bash
# Tasks to (potentially )complete post-activation of home-manager that cannot be handed by HM.
# E.g. system-level stuff that requires sudo

PREFIX=$HOME/.nix-profile

register_xsessions() {
    ln -s $PREFIX/share/xsessions/* /usr/share/xsessions/
}

register_udev_rules() {
    ln -s $PREFIX/etc/udev/rules.d/* /etc/udev/rules.d/
}

register_xdg_autostarts() {
    ln -s $PREFIX/etc/xdg/autostart/* /etc/xdg/autostart/
}

register_xsessions
register_udev_rules
# register_xdg_autostarts
