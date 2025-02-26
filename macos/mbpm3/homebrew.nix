{...}: {
  # Homebrew management
  homebrew = {
    enable = true;
    global.autoUpdate = true;
    onActivation.cleanup = "zap";
    taps = [
      "boz/repo"
    ];

    brews = [
      "gh"
      "minikube"
      "libpq"
      "cloudflared"
      "xz"
      "helm"
      "kubeseal"
      "k9s"
      "homeport/tap/dyff"
      "boz/repo/kail"
      "kustomize"
      "d2"
      "bitwarden-cli"
      "kind"
      "lnav"
      "ffmpeg"
      "git-lfs"
      "opentofu"
      "websocat"
    ];

    casks = [
      "caffeine"
      "tomighty"
      "bitwarden"
      "flameshot"
      "brave-browser"
      "rectangle"
      "discord"
      "visual-studio-code"
      "vscodium"
      "obsidian"
      "spotify"
      "alacritty"
      "iterm2"
      "docker"
      "openlens"
      "monokle"
      "pycharm-ce"
      "dbeaver-community"
      "audacity"
      "handbrake"
      "calibre"
      "megasync"
      "zotero"
      "msty"
      "firefox@developer-edition"
      "vlc"
      "linear-linear"
      "cap"
      "loom"
      "bruno"
      "macfuse"
      "mounty"
      "drawio"
      "obs"
    ];
  };
}
