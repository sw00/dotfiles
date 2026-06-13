#!/usr/bin/env bash
# Bootstrap dotfiles across macOS, WSL2, and Linux.
# Idempotent: safe to re-run. Installs prerequisites if missing,
# then symlinks configs via GNU stow.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

detect_platform() {
    case "$(uname -s)" in
        Darwin) echo macos ;;
        Linux)
            if [[ -e /proc/sys/fs/binfmt_misc/WSLInterop ]] || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
                echo wsl
            else
                echo linux
            fi
            ;;
        *) err "unsupported OS: $(uname -s)" ;;
    esac
}

normalize_hostname() {
    local h
    h="$(hostname)"
    h="${h%%.*}"
    printf '%s' "$h" | tr '[:upper:]' '[:lower:]'
}

ensure_macos_prereqs() {
    if ! xcode-select -p >/dev/null 2>&1; then
        log "installing Xcode Command Line Tools (interactive prompt)"
        xcode-select --install || true
        warn "rerun bootstrap.sh once CLT install completes"
        exit 0
    fi
    if ! command -v brew >/dev/null 2>&1; then
        log "installing Homebrew"
        NONINTERACTIVE=1 /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if   [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew    ]]; then eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
    for pkg in stow git-crypt; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            log "brew install $pkg"
            brew install "$pkg"
        fi
    done
}

# Mapping from command name → package name where they differ per manager.
# Key is the command; value is the installable package name.
_pkg_name() {
    local cmd="$1" mgr="$2"
    case "$mgr:$cmd" in
        apt:wslview)  echo wslu ;;          # wslu provides wslview on Ubuntu
        apt:git-lfs)  echo git-lfs ;;
        apt:gcc)      echo build-essential ;; # meta-package: gcc g++ make libc6-dev
        apt:make)     echo build-essential ;; # same meta-package; apt deduplicates
        apt:pstree)   echo psmisc ;;
        pacman:pstree) echo psmisc ;;
        pacman:gcc)   echo base-devel ;;
        pacman:make)  echo base-devel ;;
        *)            echo "$cmd" ;;
    esac
}

_install_pkgs() {
    local mgr="$1"; shift
    local cmds=("$@")
    local pkg_names=()
    for cmd in "${cmds[@]}"; do
        pkg_names+=("$(_pkg_name "$cmd" "$mgr")")
    done
    case "$mgr" in
        apt)    sudo apt-get update -qq && sudo apt-get install -y "${pkg_names[@]}" ;;
        dnf)    sudo dnf install -y "${pkg_names[@]}" ;;
        pacman) sudo pacman -S --noconfirm "${pkg_names[@]}" ;;
        nix)    nix-env -iA "${pkg_names[@]/#/nixpkgs.}" ;;
    esac
}

_detect_pkg_mgr() {
    if   command -v apt-get >/dev/null 2>&1; then echo apt
    elif command -v dnf     >/dev/null 2>&1; then echo dnf
    elif command -v pacman  >/dev/null 2>&1; then echo pacman
    elif command -v nix-env >/dev/null 2>&1; then echo nix
    else echo ""
    fi
}

ensure_linux_prereqs() {
    local mgr; mgr="$(_detect_pkg_mgr)"
    [[ -n "$mgr" ]] || err "no known package manager found"

    local missing=()
    for cmd in stow git-crypt; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "installing prerequisites via $mgr: ${missing[*]}"
        _install_pkgs "$mgr" "${missing[@]}"
    fi
}

ensure_system_tools() {
    # Installs only what mise cannot provide:
    #   fish    — login shell; must exist before mise activates
    #   git-lfs — git integration, not a standalone binary tool
    #   lf, tig, graphviz, pstree — not in the aqua/mise registry;
    #                               must come from system packages
    #   xclip / wslview — WSL platform integrations (no aqua equivalent)
    #   gcc, make — build tools for neovim plugins (telescope-fzf-native, mason)
    #               mapped to build-essential on apt, base-devel on pacman
    #   unzip   — required by mason to unpack tool archives
    # Everything else (tmux, neovim, fzf, devops tools, ...) is in mise.
    local mgr; mgr="$(_detect_pkg_mgr)"
    [[ -n "$mgr" ]] || { warn "no package manager — skipping system tool installation"; return 0; }

    local wanted=(fish git-lfs lf tig graphviz pstree wireguard-tools gcc make unzip)
    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        wanted+=(wslview xclip pinentry-gtk2)  # wslview from wslu; gtk pinentry for WSLg
    fi

    local missing=()
    for cmd in "${wanted[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    [[ ${#missing[@]} -eq 0 ]] && { log "system tools already installed"; return 0; }

    log "installing system tools via $mgr: ${missing[*]}"
    _install_pkgs "$mgr" "${missing[@]}"
}

ensure_fisher() {
    # Install Fisher and plugins. Runs once; fish_plugins file is the manifest.
    if ! command -v fish >/dev/null 2>&1; then
        warn "fish not installed — skipping Fisher setup"
        return 0
    fi

    local plugins="$HOME/.config/fish/fish_plugins"

    if fish -c 'functions -q fisher' 2>/dev/null; then
        log "fisher already installed"
    else
        log "installing fisher"
        fish -c '
            curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/HEAD/functions/fisher.fish \
                | source && fisher install jorgebucaran/fisher
        ' 2>&1
    fi

    if [[ -f "$plugins" ]]; then
        log "installing fish plugins"
        fish -c 'fisher update' 2>&1
    fi
}

ensure_nerd_font() {
    # Install CaskaydiaCove Nerd Font Mono — the font used in alacritty and VSCodium.
    # macOS: handled by Brewfile-base cask. Windows/WSL: handled by up.sh.
    # This function is for native Linux only.
    if fc-list 2>/dev/null | grep -qi 'CaskaydiaCove'; then
        log "CaskaydiaCove Nerd Font already installed"
        return 0
    fi

    if ! command -v fc-cache >/dev/null 2>&1; then
        warn "fontconfig not found — skipping font installation"
        return 0
    fi

    log "installing CaskaydiaCove Nerd Font"
    local tmp; tmp=$(mktemp -d)
    curl -fsSL \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip" \
        -o "$tmp/CascadiaCode.zip"

    local font_dir="$HOME/.local/share/fonts/CaskaydiaCove"
    mkdir -p "$font_dir"

    # Extract Mono variants only — these map to "CaskaydiaCove Nerd Font Mono".
    # Uses Python stdlib zipfile to avoid an unzip dependency.
    python3 - <<PYEOF
import zipfile, os
with zipfile.ZipFile('$tmp/CascadiaCode.zip') as z:
    for name in z.namelist():
        if 'NerdFontMono' in name and name.endswith('.ttf'):
            dest = os.path.join('$font_dir', os.path.basename(name))
            with open(dest, 'wb') as f:
                f.write(z.read(name))
PYEOF

    fc-cache -f "$font_dir"
    rm -rf "$tmp"
    log "CaskaydiaCove Nerd Font installed"
}

ensure_vscodium_extensions() {
    # Install VSCodium extensions from the canonical list used by all platforms.
    # macOS: called after brew bundle (which installs the VSCodium cask).
    # WSL/Windows: handled by up.sh via codium.cmd.
    local ext_file="$DOTFILES/os/wsl/windows/vscodium/extensions.txt"
    [[ -f "$ext_file" ]] || return 0

    local codium_cmd=""
    for candidate in codium codium-oss \
        "/Applications/VSCodium.app/Contents/Resources/app/bin/codium"; do
        command -v "$candidate" >/dev/null 2>&1 && codium_cmd="$candidate" && break
    done
    if [[ -z "$codium_cmd" ]]; then
        warn "codium not found — skipping VSCodium extension installation"
        return 0
    fi

    log "installing VSCodium extensions from extensions.txt"
    grep -v '^#' "$ext_file" | grep -v '^$' | while read -r ext; do
        "$codium_cmd" --install-extension "$ext" --force 2>&1 \
            | grep -v 'already installed' || true
    done
}

ensure_homebrew_bundle() {
    # Run brew bundle for each Brewfile stowed to ~.
    # Brewfile-base (os/macos) installs shared desktop apps.
    # Brewfile-host (hosts/<host>) installs machine-specific apps and deps.
    for brewfile in ~/.Brewfile-base ~/.Brewfile-host; do
        [[ -f "$brewfile" ]] || continue
        log "brew bundle --file=$brewfile"
        brew bundle --file="$brewfile"
    done
}

ensure_tmux_plugins() {
    # Plugins are sourced directly in tmux.conf (no TPM) to avoid TPM's
    # startup overhead (~8 s on WSL from repeated tmux list-keys calls).
    # This function clones each plugin if the directory is missing.
    local plugins_dir="$HOME/.config/tmux/plugins"
    mkdir -p "$plugins_dir"

    declare -A plugins=(
        [tmux-resurrect]="https://github.com/tmux-plugins/tmux-resurrect"
        [tmux-window-name]="https://github.com/ofirgall/tmux-window-name"
    )

    for name in "${!plugins[@]}"; do
        local dir="$plugins_dir/$name"
        if [[ -d "$dir" ]]; then
            log "tmux plugin already installed: $name"
        else
            log "cloning tmux plugin: $name"
            git clone --depth=1 "${plugins[$name]}" "$dir"
        fi
    done
}

ensure_sesh() {
    # sesh (joshmedeski/sesh) is not in the mise registry; install the
    # pre-built binary from GitHub releases into ~/.local/bin.
    # Asset naming: sesh_{Darwin,Linux}_{arm64,x86_64}.tar.gz
    local dest="$HOME/.local/bin/sesh"
    if [[ -x "$dest" ]]; then
        log "sesh already installed"
        return 0
    fi
    log "installing sesh (smart tmux session manager)"

    local os arch
    case "$(uname -s)" in
        Darwin) os="Darwin" ;;
        Linux)  os="Linux"  ;;
        *) warn "sesh: unsupported OS — install from https://github.com/joshmedeski/sesh"; return 0 ;;
    esac
    case "$(uname -m)" in
        arm64|aarch64) arch="arm64"  ;;
        x86_64)        arch="x86_64" ;;
        *) warn "sesh: unsupported arch $(uname -m) — install manually"; return 0 ;;
    esac

    local tmp; tmp=$(mktemp -d)
    curl -fsSL \
        "https://github.com/joshmedeski/sesh/releases/latest/download/sesh_${os}_${arch}.tar.gz" \
        -o "$tmp/sesh.tar.gz"
    tar -xzf "$tmp/sesh.tar.gz" -C "$tmp"
    mkdir -p "$HOME/.local/bin"
    install -m755 "$tmp/sesh" "$dest"
    rm -rf "$tmp"
}

ensure_mise() {
    # Install mise if absent, then install all tools from .config/mise/config.toml.
    # macOS: mise is installed by ensure_homebrew_bundle (Brewfile-base) and will
    #        already be in PATH here — the curl block below is skipped entirely.
    # Linux: no Homebrew; install from the official installer into ~/.local/bin.
    if ! command -v mise >/dev/null 2>&1; then
        log "installing mise"
        curl -fsSL https://mise.run | sh
        # Add to PATH for the remainder of this script
        export PATH="$HOME/.local/bin:$PATH"
    else
        log "mise $(mise --version) already installed"
    fi

    if [[ -f "$HOME/.config/mise/config.toml" ]]; then
        log "mise install (CLI tools + runtimes)"
        mise install --yes
    else
        warn "no mise config found at ~/.config/mise/config.toml — skipping"
    fi
}

ensure_pi() {
    # Install pi (https://pi.dev) as a global npm package via the mise-managed Node.
    # mise auto-installs node.default_packages_file entries only when provisioning
    # a *new* Node version; this function covers already-provisioned machines.
    if command -v pi >/dev/null 2>&1; then
        log "pi $(pi --version 2>/dev/null | head -1) already installed"
        return 0
    fi
    if ! command -v npm >/dev/null 2>&1; then
        warn "npm not found — skipping pi installation (re-run after mise installs Node)"
        return 0
    fi
    log "installing pi (pi.dev terminal coding agent)"
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
}

stow_dir() {
    # stow_dir <package-parent-dir> [explicit packages...]
    # Auto-discovers top-level packages if none given. No-ops if dir missing.
    # Before stowing, removes any plain (non-symlink) files in $HOME that
    # conflict with the stow package — these are typically fisher-managed files
    # from a previous fish install that are now tracked in dotfiles.  They will
    # be regenerated by ensure_fisher after stow owns the symlinks.
    local parent="$1"; shift
    [[ -d "$parent" ]] || return 0

    local pkgs=("$@")
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        local d
        while IFS= read -r -d '' d; do
            pkgs+=("$(basename "$d")")
        done < <(find "$parent" -maxdepth 1 -mindepth 1 -type d -print0)
    fi
    [[ ${#pkgs[@]} -eq 0 ]] && return 0

    log "stow $parent -> ~ (${pkgs[*]})"

    # Dry-run: detect and remove blocking targets before the real stow.
    #
    # Two kinds handled:
    #   1. Plain (non-symlink) files — "existing target is neither a link nor a directory"
    #      Typically fisher-managed files from a previous fish install that are now
    #      tracked in dotfiles.  They will be regenerated by ensure_fisher after stow
    #      owns the symlinks.
    #   2. Unowned directory symlinks — "existing target is not owned by stow"
    #      Arise when a directory was previously "folded" (whole-dir symlinked) by a
    #      different stow package (e.g. hosts/mbpm3/alacritty owned ~/.config/alacritty
    #      before base/alacritty was introduced, or during asdf→mise migration where
    #      the old stow state pre-dates --no-folding).  stow --restow refuses to touch
    #      them; we remove the symlink so stow can recreate it with per-file links.
    local _dry_out
    _dry_out=$(stow -n --no-folding -d "$parent" -t "$HOME" "${pkgs[@]}" 2>&1 || true)

    local _plain
    _plain=$(printf '%s\n' "$_dry_out" \
        | grep -oE 'existing target is neither a link nor a directory: .+' \
        | sed 's/existing target is neither a link nor a directory: //' || true)
    if [[ -n "$_plain" ]]; then
        while IFS= read -r rel; do
            [[ -z "$rel" ]] && continue
            local target="$HOME/$rel"
            if [[ -f "$target" && ! -L "$target" ]]; then
                warn "removing conflicting plain file: ~/$rel"
                rm -f "$target"
            fi
        done <<< "$_plain"
    fi

    local _unowned
    _unowned=$(printf '%s\n' "$_dry_out" \
        | grep -oE 'existing target is not owned by stow: .+' \
        | sed 's/existing target is not owned by stow: //' || true)
    if [[ -n "$_unowned" ]]; then
        while IFS= read -r rel; do
            [[ -z "$rel" ]] && continue
            local target="$HOME/$rel"
            if [[ -L "$target" ]]; then
                warn "removing unowned dir symlink: ~/$rel  (was → $(readlink "$target"))"
                rm -f "$target"
            fi
        done <<< "$_unowned"
    fi

    # Suppress the known stow BUG about absolute/relative mismatch — triggered
    # by WSL cross-filesystem symlinks (e.g. ~/Downloads -> /mnt/c/...) that
    # stow cannot own. Stow still completes correctly; the message is noise.
    stow --restow --no-folding -d "$parent" -t "$HOME" "${pkgs[@]}" \
        2> >(grep -v 'BUG in find_stowed_path' >&2)
}

load_macos_launch_agents() {
    local uid; uid="$(id -u)"
    shopt -s nullglob
    local plist
    for plist in "$HOME/Library/LaunchAgents/"*.plist; do
        # Extract the service label from the plist so we can check if it is
        # already loaded before stopping and restarting it.
        local label
        label=$(python3 -c "
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    pl = plistlib.load(f)
print(pl.get('Label', ''))
" "$plist" 2>/dev/null)
        if [[ -z "$label" ]]; then
            warn "could not read Label from $(basename "$plist") — skipping"
            continue
        fi
        if launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
            log "reloading launch agent: $label"
            launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true
            launchctl bootstrap "gui/$uid" "$plist"
        else
            log "loading launch agent: $label"
            launchctl bootstrap "gui/$uid" "$plist"
        fi
    done
    shopt -u nullglob
}

disable_rectangle_autolaunch() {
    # Rectangle is kept installed as a fallback manual tiling tool, but it
    # should not start automatically on login. AeroSpace is now the primary
    # tiling WM on macOS and starts via its own launch-on-login setting.
    local bundle_id="com.knollsoft.Rectangle"

    if ! defaults read "$bundle_id" >/dev/null 2>&1; then
        log "Rectangle not installed or never launched — skipping autolaunch disable"
        return 0
    fi

    if [[ "$(defaults read "$bundle_id" launchOnLogin 2>/dev/null)" == "0" ]]; then
        log "Rectangle launch-on-login already disabled"
    else
        log "disabling Rectangle launch-on-login"
        defaults write "$bundle_id" launchOnLogin -bool false
    fi

    # Also remove Rectangle from the system Login Items list, if present.
    # Rectangle registers a helper app (RectangleLauncher.app) as a login item;
    # setting launchOnLogin=false stops it from re-registering, but this line
    # cleans up any existing system Login Item entry.
    osascript -e 'tell application "System Events" to delete every login item whose name is "Rectangle"' >/dev/null 2>&1 || true
}

_stow_preflight() {
    # Dry-run every stow operation against $HOME to surface conflicts before
    # any real change is made.  Plain-file conflicts (e.g. fisher-managed files
    # from a prior install) are *expected* and handled automatically by
    # stow_dir; only truly unexpected conflicts (e.g. a directory that stow
    # wants to fold) are treated as fatal here.
    local conflicts=0

    _sim_stow() {
        local parent="$1"; shift
        [[ -d "$parent" ]] || return 0
        local pkgs=("$@")
        if [[ ${#pkgs[@]} -eq 0 ]]; then
            local d
            while IFS= read -r -d '' d; do
                pkgs+=("$(basename "$d")")
            done < <(find "$parent" -maxdepth 1 -mindepth 1 -type d -print0)
        fi
        [[ ${#pkgs[@]} -eq 0 ]] && return 0
        local out
        out=$(stow -n --no-folding -d "$parent" -t "$HOME" "${pkgs[@]}" 2>&1 || true)
        # Plain-file conflicts are handled by stow_dir; only flag other errors.
        local fatal
        fatal=$(echo "$out" | grep -E 'cannot stow|existing target is not a symlink' || true)
        if [[ -n "$fatal" ]]; then
            echo "$fatal" >&2
            conflicts=$((conflicts + 1))
        fi
    }

    if _repo_is_locked; then
        _sim_stow "$DOTFILES/base" git nvim fish tmux alacritty mise
    else
        _sim_stow "$DOTFILES/base" git nvim ssh fish tmux alacritty mise
    fi

    case "$platform" in
        macos) _sim_stow "$DOTFILES/os/macos" ;;
        linux) _sim_stow "$DOTFILES/os/linux" ;;
        wsl)
            _sim_stow "$DOTFILES/os/linux" bash
            _sim_stow "$DOTFILES/os/wsl" git gnupg
            ;;
    esac

    [[ -d "$DOTFILES/hosts/$host" ]] && _sim_stow "$DOTFILES/hosts/$host"

    unset -f _sim_stow

    if [[ $conflicts -gt 0 ]]; then
        err "stow conflicts detected (see above).\n  Back up or remove the conflicting files, then re-run bootstrap.sh."
    fi
}

_repo_is_locked() {
    # Detect whether git-crypt has not yet been unlocked on this clone.
    # Encrypted blobs start with a 10-byte magic header: \x00GITCRYPT\x00
    local sentinel="$DOTFILES/secrets/env.sh"
    [[ -f "$sentinel" ]] || return 1  # no secrets file — assume unlocked
    python3 -c "
import sys
with open(sys.argv[1], 'rb') as f:
    sys.exit(0 if f.read(10) == b'\x00GITCRYPT\x00' else 1)
" "$sentinel" 2>/dev/null
}

main() {
    [[ -d "$DOTFILES" ]] || err "dotfiles not at $DOTFILES (override with DOTFILES=...)"

    local platform host
    platform="$(detect_platform)"
    host="$(normalize_hostname)"
    log "platform=$platform host=$host"

    case "$platform" in
        macos)     ensure_macos_prereqs ;;
        linux|wsl) ensure_linux_prereqs ;;
    esac

    # Pre-flight: dry-run all stow operations and report conflicts clearly
    # rather than aborting mid-run with a cryptic stow error.
    _stow_preflight

    # gnupg and ssh configs include encrypted files (.ssh/config.d/*, secrets/).
    # Stowing them while git-crypt is locked installs encrypted blobs as configs.
    if _repo_is_locked; then
        warn "git-crypt is locked — skipping ssh stow"
        warn "run 'git-crypt unlock' then re-run bootstrap.sh to complete setup"
        log "stowing base configs (secrets excluded)"
        stow_dir "$DOTFILES/base" git nvim fish tmux alacritty mise
    else
        log "stowing base configs"
        stow_dir "$DOTFILES/base" git nvim ssh fish tmux alacritty mise
    fi

    # gnupg is stowed per-OS, not from base: macOS uses pinentry-ide,
    # Linux/WSL use pinentry-tty. Both sources target the same file
    # (gpg-agent.conf) so base/gnupg would cause a stow conflict.
    case "$platform" in
        macos) stow_dir "$DOTFILES/os/macos" ;;
        linux) stow_dir "$DOTFILES/os/linux" ;;
        wsl)
            # WSL: stow shell from os/linux; gnupg comes from os/wsl so the
            # VSCodium Remote pinentry wrapper (pinentry-wsl.sh) is used.
            # Alacritty runs on Windows; awesome WM is irrelevant.
            stow_dir "$DOTFILES/os/linux" bash
            # Explicit package list: os/wsl/windows/ is not a stow package.
            # gnupg: WSL-specific config pointing to pinentry-wsl.sh.
            stow_dir "$DOTFILES/os/wsl" git gnupg
            ;;
    esac

    if [[ -d "$DOTFILES/hosts/$host" ]]; then
        stow_dir "$DOTFILES/hosts/$host"
    else
        warn "no host-specific configs for '$host' (expected $DOTFILES/hosts/$host)"
    fi

    if [[ "$platform" == "macos" ]]; then
        load_macos_launch_agents
    fi

    if [[ "$platform" == "wsl" ]]; then
        log "running Windows-side setup"
        bash "$DOTFILES/os/wsl/up.sh"
    fi

    # Install tools after configs are stowed so first-launch config is ready.
    # System tools (apt/brew) first, then mise for CLI tools and runtimes.
    # Font: macOS → Brewfile cask; WSL → up.sh; Linux → ensure_nerd_font.
    case "$platform" in
        linux|wsl)
            ensure_system_tools
            ensure_fisher
            ensure_mise
            ensure_pi
            ensure_sesh
            ensure_tmux_plugins
            ;;
        macos)
            ensure_homebrew_bundle
            ensure_vscodium_extensions
            disable_rectangle_autolaunch
            ensure_fisher
            ensure_mise
            ensure_pi
            ensure_sesh
            ensure_tmux_plugins
            ;;
    esac

    if [[ "$platform" == "linux" ]]; then
        ensure_nerd_font
    fi

    log "bootstrap complete"
    log "next steps:"
    log "  1. Start a new shell (or: exec fish) to pick up Fish config"

}

main "$@"
