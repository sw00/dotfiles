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
    ];

    casks = [
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
      "pycharm-ce"
      "dbeaver-community"
      "audacity"
      "handbrake"
    ];
  };
}
