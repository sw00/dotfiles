autoload -Uz compinit promptinit
compinit
promptinit

prompt walters

# use z
. `brew --prefix`/etc/profile.d/z.sh

# load zsh functions
[[ -f ~/.zsh/functions ]] && source ~/.zsh/functions

# load local aliases
[[ -f ~/.aliases ]] && source ~/.aliases

# load local config
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# set secrets
[[ -f ~/.secrets.sh ]] && source ~/.secrets.sh

