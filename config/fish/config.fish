# MacOS locale
set -Ux LC_ALL en_US.UTF-8
set -Ux LANG en_US.UTF-8

# vim is editor
set -U EDITOR nvim

# TimeWarrior
set -x TIMEWARRIORDB "$HOME/Dropbox/etc/timewarrior"

# Jump
status --is-interactive; and . (jump shell | psub)

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


set -g fish_user_paths "/usr/local/opt/qt/bin" $fish_user_paths
