#!/usr/bin/env bash
ALACRITTY_VERSION=v0.4.1

pushd /tmp
wget https://github.com/alacritty/alacritty/releases/download/$ALACRITTY_VERSION/Alacritty-$ALACRITTY_VERSION-ubuntu_18_04_amd64.deb
sudo dpkg -i Alacritty-$ALACRITTY_VERSION-ubuntu_18_04_amd64.deb
popd
