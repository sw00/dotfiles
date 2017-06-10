# ZSH history options
HISTFILE="$HOME/.zsh_history"
HISTSIZE="10000"
SAVEHIST="10000"

setopt \
  appendhistory \
  sharehistory \
  incappendhistory \
  histignoredups \
  histignorealldups \
  histignorespace \
  histverify

# ZSH modules
autoload -Uz compinit promptinit
compinit
promptinit

# Miscellaneous
setopt \
  autocd \
  extendedglob \
  nomatch \
  notify

unsetopt beep

export EDITOR="vi"

bindkey '^R' history-incremental-search-backward
bindkey -e # emacs prompt

# case insensitive tab completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# load zsh functions
for function in ~/.zsh/*; do
  source $function
done

# load local aliases
[[ -f ~/.aliases ]] && source ~/.aliases

# load local config
[[ $(uname -s) = 'Darwin' ]] && source ~/.zshrc.osx
[[ $(uname -s) = 'Linux' ]] && source ~/.zshrc.nix

# set secrets
[[ -f ~/.secrets.sh ]] && source ~/.secrets.sh

