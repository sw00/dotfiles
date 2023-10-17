{ config, pkgs, ... }:
let pkgs = import (builtins.fetchTarball {
            url = "https://github.com/NixOS/nixpkgs/archive/refs/tags/23.05.tar.gz";
            }) {};
in

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
    ./nixfiles/gpg.nix
    ./nixfiles/fish.nix
    ./nixfiles/cli.nix
    ./nixfiles/tmux.nix
    ./nixfiles/neovim.nix
    ./nixfiles/git.nix
    ./nixfiles/python.nix
    ./nixfiles/rust.nix
    # ./nixfiles/java.nix
    ./nixfiles/ruby.nix
    ./nixfiles/wtc.nix
  ];

  home.username = "sett";
  home.homeDirectory = "/home/sett";

  home.stateVersion = "23.05";

  # Default LANG
  home.language.base = "en_US.UTF-8";

  # Let home manager install and manage itself.
  programs.home-manager.enable = true;

  # Packages to be installed
  home.packages = with pkgs; [
    git git-crypt gnupg tig
    wget zip unzip gnumake gcc pkg-config openssl
    nodejs # for lsp
    dbus gnome.gnome-keyring
    wslu
    bitwarden-cli
  ];
}
