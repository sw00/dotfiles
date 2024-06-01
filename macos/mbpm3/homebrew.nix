{...}: {
  # Homebrew management
  homebrew = {
    enable = true;
    global.autoUpdate = true;
    onActivation.cleanup = "zap";
    brews = [
      "gh"
      "minikube"
      "libpq"
      "cloudflared"
      "xz"
      "helm"
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
