{...}: {
  # Homebrew management
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";
    brews = [
      "gh"
      "minikube"
      "libpq"
      "cloudflared"
      "xz"
    ];

    casks = [
      "bitwarden"
      "flameshot"
      "brave-browser"
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
