# locale
set -x LC_ALL en_US.UTF-8

# TimeWarrior
set -x TIMEWARRIORDB "$HOME/Dropbox/etc/timewarrior"

# cabal
set -g fish_user_paths ~/.cabal/bin $fish_user_paths

# autojump
[ -f /usr/local/share/autojump/autojump.fish ]; and source /usr/local/share/autojump/autojump.fish

source ~/.config/fish/functions/fish_user_aliases.fish

