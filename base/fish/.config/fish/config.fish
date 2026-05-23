# ── Environment ───────────────────────────────────────────────────────────────
set -gx EDITOR nvim

# Source secrets env file (bash export KEY=VALUE syntax).
# Guards: file must exist and not be a git-crypt encrypted blob.
set -l _secrets ~/dotfiles/secrets/env.sh
if test -f $_secrets
    and not string match -q (string sub -l 9 (cat $_secrets 2>/dev/null)) "\x00GITCRYPT"
    grep -E '^export [A-Za-z_][A-Za-z0-9_]*=' $_secrets 2>/dev/null \
        | string replace 'export ' '' \
        | while read -l _line
            set -l _kv (string split -m1 '=' -- $_line)
            test (count $_kv) -ge 2; and set -gx $_kv[1] $_kv[2]
        end
end

# ── PATH ──────────────────────────────────────────────────────────────────────
fish_add_path ~/bin
fish_add_path ~/.local/bin

# ── mise (version manager) ────────────────────────────────────────────────────
# --shims mode: prepends ~/.local/share/mise/shims to PATH and exits.
# Shims resolve the correct tool version per-directory at invocation time,
# so per-project .mise.toml still works. Avoids the ~76ms hook-env scan that
# `mise activate fish` (dynamic mode) runs on every shell startup.
if command -q mise
    mise activate --shims fish | source
end

# ── Homebrew (macOS only) ─────────────────────────────────────────────────────
if test -d /opt/homebrew/bin
    eval (/opt/homebrew/bin/brew shellenv)
end

# ── Tool integrations ─────────────────────────────────────────────────────────
# zoxide — smart cd (replaces z/autojump)
if command -q zoxide
    zoxide init fish | source
end

# direnv — per-directory environment variables
if command -q direnv
    direnv hook fish | source
end

# ── GPG agent ─────────────────────────────────────────────────────────────────
set -gx GPG_TTY (tty)
if command -q gpg-connect-agent
    gpg-connect-agent updatestartuptty /bye >/dev/null
end

# ── Interactive shell only ────────────────────────────────────────────────────
status --is-interactive; or return

# Abbreviations
abbr --add --global -- doco  'docker compose'
abbr --add --global -- ipy   ipython
abbr --add --global -- kc    kubectl
abbr --add --global -- kn    kubens
abbr --add --global -- kx    kubectx

# Aliases
alias vi  nvim
alias vim nvim

# fzf keybindings (patrickf1/fzf.fish)
if functions -q _fzf_search_directory
    bind \ct _fzf_search_directory
end
