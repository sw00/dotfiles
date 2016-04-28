#!/bin/bash
set -e

BASE_DIR="$(dirname ${BASH_SOURCE})"
cd $BASE_DIR;

git pull origin master;

function vim() {
    echo "Bootstrapping vim config"
    git submodule update
    rsync --exclude ".git/" -avh --no-perms "${BASE_DIR}/vim/" ~/.vim
}

function zsh(){
    echo "Bootstrapping zsh config"
    ln -sf "${BASE_DIR}/zshrc" ~/.zshrc
    [[ "$OSTYPE" = "darwin"* ]] && ln -sf "${BASE_DIR}/zshrc.osx" ~/.zshrc.local
}

function tmux(){
    echo "Bootstrapping tmux config"
    ln -sf "${BASE_DIR}/tmux.conf" ~/.tmux.conf
}

INIT_LIST=(vim zsh tmux)

for func in ${INIT_LIST[@]}
do
    $func
    unset $func
done
