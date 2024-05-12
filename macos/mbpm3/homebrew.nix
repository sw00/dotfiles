{...}: {
  # Homebrew management
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";
    brews = [
      "minikube"
      "kubectx"
      "azure-cli"
    ];

    casks = [
      "bitwarden"
      "flameshot"
      "brave-browser"
      "discord"
      "visual-studio-code"
      "spotify"
      "alacritty"
      "iterm2"
      "docker"
      "openlens"
    ];
  };
}
