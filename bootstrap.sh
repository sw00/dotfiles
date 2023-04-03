#!/usr/bin/env bash
home-manager -f home.nix switch -b backup

host_dir=./host-$(hostname -s)

[[ -d $host_dir ]] && \
    pushd $host_dir && . up.sh && popd
