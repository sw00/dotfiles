#!/usr/bin/env bash
# Edit and applies home-manager configuration

profile=${1:-sett@x1c2e}

set -e

pushd ~/dotfiles/home-manager/

$EDITOR home.nix

if git diff --quiet '*.nix'; then
    echo "No changes detected, exiting."
    popd
    exit 0
fi

# show changes
git diff -U0 '*.nix'

popd

echo "Home Manager switching to new generation..."

home-manager --flake .#$profile switch --impure &>hm-switch.log || (cat hm-switch.log | grep --color error && exit 1)

current=$(home-manager generations | head -n1)

git commit -am "$current"

notify-send -e "Home Manager generation switched OK!" --icon=software-update-available
