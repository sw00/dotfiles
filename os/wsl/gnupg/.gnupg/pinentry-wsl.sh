#!/bin/sh
# pinentry-wsl.sh — smart pinentry dispatcher for WSL2.
#
# gpg-agent invokes this script whenever a passphrase is needed.
# gpg-agent forwards the client's DISPLAY/WAYLAND_DISPLAY via the Assuan
# UPDATESTARTUPTTY command, so the variables are available here even when
# the agent itself was started without a display.
#
# Priority:
#   1. GTK GUI via WSLg — uses $DISPLAY set by WSLg (:0) to render a native
#      Windows dialog box.  Works from VSCodium Remote WSL server (no TTY)
#      and from Alacritty/terminal sessions alike.
#   2. curses — fallback for terminal sessions without a display (e.g. pure
#      SSH forwarding without -X, or Windows 10 WSL without WSLg).
#   3. tty   — last resort; will fail gracefully if no TTY is attached.
#
# Requires: pinentry-gtk-2   (sudo apt-get install pinentry-gtk-2)
#           pinentry-curses  (installed by default with gnupg2)

PINENTRY_GTK=/usr/bin/pinentry-gtk-2
PINENTRY_CURSES=/usr/bin/pinentry-curses
PINENTRY_TTY=/usr/bin/pinentry-tty

if [ -n "$DISPLAY" ] && [ -x "$PINENTRY_GTK" ]; then
    exec "$PINENTRY_GTK" "$@"
fi

if [ -x "$PINENTRY_CURSES" ]; then
    exec "$PINENTRY_CURSES" "$@"
fi

exec "$PINENTRY_TTY" "$@"
