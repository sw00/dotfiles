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

# use z
. `brew --prefix`/etc/profile.d/z.sh

# extraction magick
extract () {
    if [ -f $1 ] ; then
        case $1 in
            *.tar.bz2)        tar xjf $1        ;;
            *.tar.gz)         tar xzf $1        ;;
            *.bz2)            bunzip2 $1        ;;
            *.rar)            unrar x $1        ;;
            *.gz)             gunzip $1         ;;
            *.tar)            tar xf $1         ;;
            *.tbz2)           tar xjf $1        ;;
            *.tgz)            tar xzf $1        ;;
            *.zip)            unzip $1          ;;
            *.Z)              uncompress $1     ;;
            *)                echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}
