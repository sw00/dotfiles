autoload -Uz vcs_info
setopt PROMPT_SUBST

zstyle ':vcs_info:git:*' stagedstr '%B%F{yellow}+%f%b'
zstyle ':vcs_info:git:*' unstagedstr '%B%F{red}*%f%b'
zstyle ':vcs_info:git:*' formats '[%b%u%c]'
zstyle ':vcs_info:git:*' check-for-staged-changes true
zstyle ':vcs_info:git:*' check-for-changes true

job="%1(j.%B%F{red}*%f%b.)"
PROMPT="%B%(?..[%?] )%b%n@%U%m%u$job> "

set_prompt() { 
	RPROMPT="%F{green}%16<..<%~%f%<< $vcs_info_msg_0_"
}

precmd_functions+=( vcs_info set_prompt )

