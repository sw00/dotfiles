#!/bin/bash
set -e

BASE_DIR="$(pwd ${BASH_SOURCE})"
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

function spacemacs(){
    echo "Bootstrapping spacemacs config"
    ln -sf "${BASE_DIR}/spacemacs" ~/.spacemacs
}

function leiningen(){
    echo "Bootstrapping leiningen config"
    [[ ! -d ~/.lein ]] && mkdir ~/.lein
    ln -sf "${BASE_DIR}/lein/profiles.clj" ~/.lein/profiles.clj
}

INIT_LIST=(vim zsh tmux spacemacs leiningen)

for func in ${INIT_LIST[@]}
do
    $func
    unset $func
done

unset BASE_DIR
