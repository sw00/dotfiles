#!/usr/bin/env bash
# Rebuilds nixos configuration and commits on success.

host=${1:-x1c2e}

set -e

# cd into host config dir
pushd ~/dotfiles/nixos/$host

$EDITOR configuration.nix

if git diff --quiet '*.nix'; then
    echo "No changes detected, exiting."
    popd
    exit 0
fi

# show changes
git diff -U0 '*.nix'

popd

echo "NixOS rebuilding..."

sudo nixos-rebuild --flake .#$host switch &>nixos-switch.log || (cat nixos-switch.log | grep --color error && exit 1)

# Get current generation metadata
current=$(nixos-rebuild list-generations | grep current)

# Commit all changes witih the generation metadata
git commit -am "$current"

popd

# Notify all OK!
notify-send -e "NixOS Rebuilt OK!" --icon=software-update-available
