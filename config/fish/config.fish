# TimeWarrior
set -x TIMEWARRIORDB "$HOME/Dropbox/etc/timewarrior"

# cabal
set -g fish_user_paths ~/.cabal/bin $fish_user_paths

# autojump
[ -f /usr/local/share/autojump/autojump.fish ]; and source /usr/local/share/autojump/autojump.fish
