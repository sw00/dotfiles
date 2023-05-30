#!/usr/bin/env bash

sysinfo=$(uname -a)
if $(echo $sysinfo | grep -qi wsl); then
    machine_os=wsl
elif $(echo $sysinfo | grep -qi darwin); then
    machine_os=macos
else
    machine_os=linux
fi

home-manager -f home.nix switch -b backup

if [[ $1 = --all ]]; then
    host_dir=./host-$(hostname -s)

    [[ $machine_os = 'wsl' ]] && \
        cp config/alacritty/* $(wslpath $(wslvar APPDATA))/alacritty/

    [[ -d $host_dir ]] && \
        pushd $host_dir && . up.sh && popd
fi
