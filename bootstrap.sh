#!/usr/bin/env bash
# Bootstrap the dotfiles configurations

DOTFILES="$HOME/dotfiles"

# Install base configuration for all hosts
echo "Installing base configurations..."
stow --restow -d ~/dotfiles/base -t ~ bash git nvim ssh fish tmux

# Detect and install OS-specific configurations
if [ "$(uname)" == "Darwin" ]; then
    echo "Installing macOS configurations..."
    OS_TYPE=macos
elif [ "$(uname)" == "Linux" ]; then
    echo "Installing Linux configurations..."
    OS_TYPE=linux
fi

# Find all directories under os-specific folder and stow them
find "$DOTFILES/os/$OS_TYPE" -maxdepth 1 -type d -not -path "$DOTFILES/os/$OS_TYPE" -exec basename {} \; | xargs -I{} stow --restow -d "$DOTFILES/os/$OS_TYPE" -t ~ {}

# Detect and install host-specific configurations
HOSTNAME=$(hostname)
if [ -d "$DOTFILES/hosts/$HOSTNAME" ]; then
    echo "Installing configurations for host: $HOSTNAME"
    # Find all directories in the host-specific folder and stow them
    find "$DOTFILES/hosts/$HOSTNAME" -maxdepth 1 -type d -not -path "$DOTFILES/hosts/$HOSTNAME" -exec basename {} \; | xargs -I{} stow --restow -d "$DOTFILES/hosts/$HOSTNAME" -t ~ {}
else
    echo "No host-specific configurations found for: $HOSTNAME"
fi

echo "Dotfiles installation complete!"
