alias ..="cd .."
alias ...="cd ../.."

alias vi="nvim"
alias vim="nvim"

# alias xdg-open to open if on linux
which open 2>&1 > /dev/null
[[ $? != 0 ]] && alias open='xdg-open'

alias abacaxi="brew update && brew doctor && brew outdated"
alias doco="docker-compose"
alias doma=docker-machine

# git
alias gco="git checkout"
alias gst="git status"
alias gc="git commit"
alias ga="git add"
alias gl="git log"
alias gd="git diff"

# python
alias py2venv="python2 -m virtualenv"
alias py3venv="python3 -m venv"