case $META_OS in
	'macos')
		alias abacaxi='brew update && brew doctor && brew outdated'
		;;
	'wsl')
		alias abacaxi='sudo apt update'
		alias open='wslview'
		;;
	'linux')
		alias open='xdg-open'
		;;
esac

# general
alias ..="cd .."
alias ...="cd ../.."


# neovim
if [[ -n $(which nvim) ]]; then
	alias vi="nvim"
	alias vim="nvim"
fi

# docker
if [[ -n $(which docker) ]]; then
	alias doco=docker-compose
	alias doma=docker-machine
fi

# git
alias gco 2>/dev/null >/dev/null 
if [[ $? != 0 ]]; then
	alias gco="git checkout"
	alias gst="git status"
	alias gc="git commit"
	alias ga="git add"
	alias gl="git log"
	alias gd="git diff"
fi

# python
alias py2venv="python2 -m virtualenv"
alias py3venv="python3 -m venv"
