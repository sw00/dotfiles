autoload -Uz compinit promptinit
compinit
promptinit

export EDITOR="vi"
HISTFILE="$HOME/.zsh_history"
HISTSIZE="10000"
SAVEHIST="10000"

setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY


setopt AUTO_CD

bindkey '^R' history-incremental-search-backward
bindkey -e # emacs prompt

# case insensitive tab completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# use z
. `brew --prefix`/etc/profile.d/z.sh

# load zsh functions
for function in ~/.zsh/*; do
  source $function
done

source /usr/local/opt/zsh-history-substring-search/zsh-history-substring-search.zsh

# load local aliases
[[ -f ~/.aliases ]] && source ~/.aliases

# load local config
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# set secrets
[[ -f ~/.secrets.sh ]] && source ~/.secrets.sh


[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export PATH="/usr/local/opt/qt/bin:$PATH"
