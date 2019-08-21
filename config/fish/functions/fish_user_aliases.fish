if command -sq nvim
	alias vi='nvim'
	alias vim='nvim'
end

if [ (uname -s) = 'Darwin' ]
	alias opn='open'
	alias abacaxi='brew update ; and brew doctor ; and brew outdated'
else
	alias opn='xdg-open'
	grep -q Microsoft /proc/version; and alias opn='wslview'
end

alias gco='git checkout'
alias gst='git status'
alias gc='git commit'
alias ga='git add'
alias gl='git log'
alias gd='git diff'

alias doco='docker-compose'
alias doma='docker-machine'
