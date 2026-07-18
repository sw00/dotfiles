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
    #   tig, graphviz, pstree — not in the aqua/mise registry and no prebuilt
    #                           binaries for the ubi backend; system packages only
    #   xclip / wslview — WSL platform integrations (no aqua equivalent)
    #   gcc, make — build tools for neovim plugins (telescope-fzf-native, mason)
    #               mapped to build-essential on apt, base-devel on pacman
    #   unzip   — required by mason to unpack tool archives
    # Everything else (tmux, neovim, fzf, git-lfs, lf, sesh, devops tools, ...)
    # is in mise.
    local mgr; mgr="$(_detect_pkg_mgr)"
    [[ -n "$mgr" ]] || { warn "no package manager — skipping system tool installation"; return 0; }

    local wanted=(fish tig graphviz pstree wireguard-tools gcc make unzip)
    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        wanted+=(wslview xclip pinentry-gtk2)  # wslview from wslu; gtk pinentry for WSLg
    else
        # Native Linux (incl. dual-boot Pop!_OS):
        #   alacritty — the terminal; under WSL it runs on the Windows side
        #   xclip     — tmux copy-mode clipboard (tmux.conf Linux branch)
        wanted+=(alacritty xclip)
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

migrate_app_trim() {
    # 2026-07 app-trim migration (lean core-apps pass). Uninstalls casks removed
    # from the Brewfiles and finishes the Docker Desktop → colima move.
    # Every step is guarded, so this is a no-op once a machine has migrated.
    # Delete this function (and its call) once all macs have bootstrapped past it.
    #
    # Note: user data is intentionally NOT removed — Zotero's library, Docker
    # Desktop's VM disk (~/Library/Containers/com.docker.docker), and app prefs
    # stay on disk. Delete those by hand if unwanted.
    local trimmed=(
        gpg-suite httpie-desktop calibre zotero
        caffeine mouseless appcleaner rectangle libreoffice
        megasync dbeaver-community docker-desktop
    )
    local cask
    for cask in "${trimmed[@]}"; do
        if brew list --cask "$cask" >/dev/null 2>&1; then
            log "uninstalling trimmed cask: $cask"
            brew uninstall --cask "$cask" \
                || warn "could not uninstall $cask — remove manually"
        fi
    done

    # megasync: its stow package was deleted, leaving a dangling LaunchAgent
    # symlink that stow cannot unstow. Boot out and remove it.
    local mega_agent="$HOME/Library/LaunchAgents/mega.mac.megaupdater.plist"
    if [[ -L "$mega_agent" ]]; then
        log "removing stale megasync LaunchAgent"
        launchctl bootout "gui/$(id -u)/mega.mac.megaupdater" >/dev/null 2>&1 || true
        rm -f "$mega_agent"
    fi

    # colima (installed by Brewfile-host just now): finish the Docker Desktop
    # replacement — CLI plugins on ~/.docker/cli-plugins and a running VM.
    if command -v colima >/dev/null 2>&1; then
        local plugins_dir="$HOME/.docker/cli-plugins"
        mkdir -p "$plugins_dir"
        local plugin src
        for plugin in docker-compose docker-buildx; do
            src="$(brew --prefix)/opt/$plugin/bin/$plugin"
            if [[ -x "$src" && ! -e "$plugins_dir/$plugin" ]]; then
                log "linking docker CLI plugin: $plugin"
                ln -sfn "$src" "$plugins_dir/$plugin"
            fi
        done
        if ! colima status >/dev/null 2>&1; then
            log "starting colima VM (first start downloads the image — slow)"
            colima start || warn "colima start failed — run 'colima start' manually"
        fi
    fi
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
    # stow < 2.4.1: "existing target is neither a link nor a directory: <target>"
    # stow 2.4.1+: "cannot stow <source> over existing target <target> since neither a link nor a directory"
    _plain=$(printf '%s\n' "$_dry_out" \
        | grep -oE '(existing target is neither a link nor a directory: |cannot stow .+ over existing target ).+' \
        | sed -E 's/(existing target is neither a link nor a directory: |cannot stow .+ over existing target )//' \
        | sed 's/ since neither a link nor a directory.*//' || true)
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

ensure_macos_gpg() {
    # gpg-agent does NOT expand ~ in pinentry-program, so gpg-agent.conf
    # must be written with $HOME expanded at install time — same pattern as
    # the WSL pinentry in os/wsl/up.sh.  pinentry-ide.sh is stowed (static,
    # no $HOME in it); only the conf is generated here.
    mkdir -p "$HOME/.gnupg"
    chmod 700 "$HOME/.gnupg"
    [ -L "$HOME/.gnupg/gpg-agent.conf" ] && rm -f "$HOME/.gnupg/gpg-agent.conf"
    log "writing ~/.gnupg/gpg-agent.conf (pinentry-ide, \$HOME expanded)"
    cat > "$HOME/.gnupg/gpg-agent.conf" << EOF
# gpg-agent.conf — macOS  (written by bootstrap.sh; \$HOME expanded at install time)
#
# pinentry-ide.sh dispatches to PyCharm's IDE pinentry when invoked from
# the JetBrains VCS tooling (PINENTRY_USER_DATA=IJ_PINENTRY*); otherwise
# falls through to Homebrew's pinentry-mac for a normal GUI prompt.
pinentry-program $HOME/.gnupg/pinentry-ide.sh
default-cache-ttl 3600
max-cache-ttl 86400
EOF
    chmod +x "$HOME/.gnupg/pinentry-ide.sh" 2>/dev/null || true
    gpg-connect-agent reloadagent /bye >/dev/null 2>&1 || true
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
        _sim_stow "$DOTFILES/base" git nvim fish pi tmux alacritty mise
    else
        _sim_stow "$DOTFILES/base" git nvim ssh fish pi tmux alacritty mise
    fi

    case "$platform" in
        macos) _sim_stow "$DOTFILES/os/macos" ;;
        linux) _sim_stow "$DOTFILES/os/linux" ;;
        wsl)
            _sim_stow "$DOTFILES/os/linux" bash
            _sim_stow "$DOTFILES/os/wsl" git gnupg alacritty
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
        stow_dir "$DOTFILES/base" git nvim fish pi tmux alacritty mise
    else
        log "stowing base configs"
        stow_dir "$DOTFILES/base" git nvim ssh fish pi tmux alacritty mise
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
            # Alacritty runs on Windows, so only os/linux/bash is relevant here.
            stow_dir "$DOTFILES/os/linux" bash
            # Explicit package list: os/wsl/windows/ is not a stow package.
            # gnupg: WSL-specific config pointing to pinentry-wsl.sh.
            # alacritty: WSL platform variant (wsl.exe shell); up.sh copies it
            #            to Windows. Stowing keeps the WSL-side tree complete
            #            and matches the os/linux layout on native Linux.
            stow_dir "$DOTFILES/os/wsl" git gnupg alacritty
            ;;
    esac

    if [[ -d "$DOTFILES/hosts/$host" ]]; then
        stow_dir "$DOTFILES/hosts/$host"
    else
        warn "no host-specific configs for '$host' (expected $DOTFILES/hosts/$host)"
    fi

    if [[ "$platform" == "macos" ]]; then
        load_macos_launch_agents
        ensure_macos_gpg
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
            ensure_tmux_plugins
            ;;
        macos)
            ensure_homebrew_bundle
            migrate_app_trim
            ensure_vscodium_extensions
            ensure_fisher
            ensure_mise
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
