# Auto-install Fisher if not installed
if not functions -q fisher
    set -q XDG_CONFIG_HOME; or set XDG_CONFIG_HOME ~/.config
    curl -sL https://git.io/fisher | source && fisher install jorgebucaran/fisher
    
    # If you have a fish_plugins file, install those plugins too
    if test -f $XDG_CONFIG_HOME/fish/fish_plugins
        fisher update
    end
    
    echo "Fisher has been installed"
end

# Environment variables
set -gx EDITOR nvim
fenv source $HOME/dotfiles/secrets/env.sh

# add directories to PATH
fish_add_path ~/.asdf/shims

# Initialize Homebrew if available
if test -d /opt/homebrew/bin
    eval (/opt/homebrew/bin/brew shellenv)
end

# Startup GPG agent
set -x GPG_TTY (tty)
gpg-connect-agent updatestartuptty /bye >/dev/null

status --is-login; and begin
    # Login shell initialisation
end

status --is-interactive; and begin
    # Abbreviations
    abbr --add --global -- doco 'docker compose'
    abbr --add --global -- flyl 'fly -t lelapa'
    abbr --add --global -- ipy ipython
    abbr --add --global -- kc kubectl
    abbr --add --global -- kn kubens
    abbr --add --global -- kx kubectx

    # Aliases
    alias vi nvim
    alias vim nvim

    # Start tmux if not already in tmux (for Alacritty)
    if status is-interactive
        and not set -q TMUX
        tmux new-session -As 0 || tmux attach-session -d
    end
end
