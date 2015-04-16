# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

# theme to load from ~/.oh-my-zsh/themes/
ZSH_THEME="sett"

# zsh-specific aliases
alias zshconfig="vi ~/.zshrc"
alias ohmyzsh="vi ~/.oh-my-zsh"

# disable command auto-correct
DISABLE_CORRECTION="true"

# disable setting terminal title automatically
DISABLE_AUTO_TITLE="false"

# disable marking untracked files in repos as dirty (for speed)
DISABLE_UNTRACKED_FILES_DIRTY="true"

# load some plugins from ~/.oh-my-zsh/plugins/*)
plugins=(osx colorize git git-extras pip python tmux virtualenvwrapper)

source $ZSH/oh-my-zsh.sh

# use vim
export EDITOR=vim

# the PATH
PATH=/usr/local/bin:/usr/local/sbin:$PATH

# load local aliases
[[ -f ~/.aliases ]] && source ~/.aliases

# load local config
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
