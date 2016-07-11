autoload -Uz compinit promptinit
compinit
promptinit

export EDITOR="/usr/local/bin/vim"

bindkey '^R' history-incremental-search-backward

# case insensitive tab completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# use z
. `brew --prefix`/etc/profile.d/z.sh

# load zsh functions
for function in ~/.zsh/*; do
  source $function
done

# load local aliases
[[ -f ~/.aliases ]] && source ~/.aliases

# load local config
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# set secrets
[[ -f ~/.secrets.sh ]] && source ~/.secrets.sh

