set -U EDITOR vim

# TimeWarrior
set -x TIMEWARRIORDB "$HOME/Dropbox/etc/timewarrior"

# pyenv-virtualenv
status --is-interactive; and source (pyenv virtualenv-init -|psub)

# Aliases
alias abacaxi='brew update ; and brew doctor ; and brew outdated'

alias vi=nvim
alias vim=nvim

alias gco='git checkout'
alias gst='git status'
alias gc='git commit'
alias ga='git add'
alias gl='git log'
alias gd='git diff'

alias doco='docker-compose'
alias doma='docker-machine'


