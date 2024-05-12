{
  pkgs,
  self,
  ...
}: {
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = with pkgs; [
    vim
  ];

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  # nix.package = pkgs.nix;

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true; # default shell on catalina
  programs.fish.enable = true;

  # Append nix-darwin bins to system path
  environment.systemPath = [ /run/current-system/sw/bin ];

  # Register the shells
  environment.shells = with pkgs; [ bashInteractive zsh fish ];

  # Set Git commit hash for darwin-version.
  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = "mbpm3";

  # User
  users.users.sett = {
    name = "sett";
    home = "/Users/sett";
    shell = pkgs.fish;
  };

  # Homebrew management
  homebrew = {
    enable = true;
    brews = [
      "git"
      "git-crypt"
      "minikube"
      "kubectx"
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

  # Remap keys
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
    nonUS.remapTilde = true;
  };

}
