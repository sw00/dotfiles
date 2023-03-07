{ config, pkgs, ... }:

{
  # Assume non-NixOS Linux:
  targets.genericLinux.enable = true;

  imports = [
    ./nixfiles/fish.nix
  ];

  home.username = "sett";
  home.homeDirectory = "/home/sett";

  home.stateVersion = "22.05";

  # Let home manager install and manage itself.
  programs.home-manager.enable = true;

  # Packages to be installed
  home.packages = with pkgs; [
    fish git
  ];

}
