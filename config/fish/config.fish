source ~/.config/fish/functions/fish_user_aliases.fish

status --is-interactive; and source (pyenv init -|psub)

fzf_key_bindings
