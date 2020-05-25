if command -sq nvim
	alias vi='nvim'
	alias vim='nvim'
end

if [ (uname -s) = 'Darwin' ]
	alias opn='open'
	alias abacaxi='brew update ; and brew doctor ; and brew outdated'
else
	alias opn='xdg-open'
	if grep -iq Microsoft /proc/version
		alias opn='wslview'
		alias psh='powershell.exe -Command '
	end
end

alias gco='git checkout'
alias gst='git status'
alias gc='git commit'
alias ga='git add'
alias gl='git log'
alias gd='git diff'

alias doco='docker-compose'
alias doma='docker-machine'

alias kc='kubectl'
