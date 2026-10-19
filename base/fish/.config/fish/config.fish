# ── Environment ───────────────────────────────────────────────────────────────
set -gx EDITOR nvim

# Source secrets env file (native fish syntax).
set -l _secrets ~/dotfiles/secrets/env.fish
if test -f $_secrets
    set -l first_line (head -n 1 $_secrets 2>/dev/null)
    if string match -q "set*" $first_line
        source $_secrets
    end
end

# ── Homebrew (macOS only) ─────────────────────────────────────────────────────
# Deliberately FIRST of the PATH blocks: the mise block below needs `mise` on
# PATH, and on a clean shell the only mise is Homebrew's. With this block last
# (as it was until now) `command -q mise` failed and mise never activated at all
# unless Homebrew's vendor_conf.d drop-in had already run — see conf.d/mise.fish.
if test -d /opt/homebrew/bin
    eval (/opt/homebrew/bin/brew shellenv)
end

# ── PATH ──────────────────────────────────────────────────────────────────────
fish_add_path ~/bin
fish_add_path ~/.local/bin

# ── mise (version manager) ────────────────────────────────────────────────────
# --shims mode: prepends ~/.local/share/mise/shims to PATH and exits.
# Shims resolve the correct tool version per-directory at invocation time,
# so per-project .mise.toml still works. Avoids the ~76ms hook-env scan that
# `mise activate fish` (dynamic mode) runs on every shell startup.
#
# LAST of the PATH blocks on purpose: the shims dir must precede
# /opt/homebrew/bin, or brew quietly wins every name collision (it was taking
# d2, lf, websocat, hcl2json and git-lfs — the mise copies never ran).
# ~/.local/bin stays behind the shims so mise keeps owning the tools it declares
# (sesh); pi and claude are unaffected either way because they have no shims —
# _ensure_self_managed in bootstrap.sh keeps it that way.
if command -q mise
    mise activate --shims fish | source
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
# GPG_TTY must be exported to all shells (including non-interactive) so that
# gpg can find the terminal for passphrase prompts started by git/scripts.
set -gx GPG_TTY (tty)

# ── Interactive shell only ────────────────────────────────────────────────────
status --is-interactive; or return

# Disable the default fish greeting (MOTD)
set -g fish_greeting

# updatestartuptty tells gpg-agent which TTY to use for pinentry.
# Interactive-only: non-interactive shells (VSCodium server, scripts) have
# no meaningful TTY and would just block or error.
if command -q gpg-connect-agent
    gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
end

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

# Pi
fish_add_path "$HOME/.local/bin"
