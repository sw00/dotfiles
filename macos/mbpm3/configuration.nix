{
  pkgs,
  self,
  lib,
  config,
  ...
}: {
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = with pkgs; [];

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  # nix.package = pkgs.nix;

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true; # default shell on catalina
  programs.fish.enable = true;
  programs.fish.loginShellInit = let
    dquote = str: "\"" + str + "\"";

    makeBinPathList = map (path: path + "/bin");
  in ''
    fish_add_path --move --prepend --path ${lib.concatMapStringsSep " " dquote (makeBinPathList config.environment.profiles)}
    set fish_user_paths $fish_user_paths
  '';

  # Append nix-darwin bins to system path
  environment.systemPath = [/run/current-system/sw/bin];

  # Register the shells
  environment.shells = with pkgs; [bashInteractive zsh fish];

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

  # Remap keys
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
    nonUS.remapTilde = true;
  };

  system.defaults.NSGlobalDomain."com.apple.keyboard.fnState" = true;
  system.defaults.dock.autohide = true;
}
