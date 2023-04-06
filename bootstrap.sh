#!/usr/bin/env bash
home-manager -f home.nix switch -b backup

chmod 0600 ~/.ssh/*_rsa

host_dir=./host-$(hostname -s)

[[ -d $host_dir ]] && \
    pushd $host_dir && . up.sh && popd
