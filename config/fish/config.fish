# locale
set -x LC_ALL en_US.UTF-8

# editor
set -x EDITOR nvim

# TimeWarrior
set -x TIMEWARRIORDB "$HOME/Dropbox/etc/timewarrior"

# cabal
set -g fish_user_paths ~/.cabal/bin $fish_user_paths

# autojump
[ -f /usr/local/share/autojump/autojump.fish ]; and source /usr/local/share/autojump/autojump.fish

# pyenv
status --is-interactive; and source (pyenv init -|psub)

source ~/.config/fish/functions/fish_user_aliases.fish

