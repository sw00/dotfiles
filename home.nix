{ config, pkgs, ... }:

{
  # Assume non-NixOS Linux:
  targets.genericLinux.enable = true;

  # Enable nix experimental features
  xdg.configFile."nix.conf" = {
    target = "./nix";
    source = ./config/nix;
  };

  imports = [
    ./nixfiles/dotfiles.nix
    ./nixfiles/fish.nix
    ./nixfiles/neovim.nix
    ./nixfiles/git.nix
    ./nixfiles/rust.nix
    ./nixfiles/java.nix
  ];

  home.username = "sett";
  home.homeDirectory = "/home/sett";

  home.stateVersion = "22.11";

  # Default LANG
  home.language.base = "en_US.UTF-8";

  # Let home manager install and manage itself.
  programs.home-manager.enable = true;

  # Packages to be installed
  home.packages = with pkgs; [
    git
    fzf ripgrep fd autojump
    gnumake
    doctl
    nodejs # for lsp
    gcc
  ];
}
