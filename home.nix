{ config, pkgs, ... }:
let 
  pkgs = import (builtins.fetchTarball {
            url = "https://github.com/NixOS/nixpkgs/archive/refs/tags/23.11.tar.gz";
            }) {};

  username = "sett";
  homeDir = "/home/${username}";

  machine_os = if builtins.pathExists "/proc/sys/fs/binfmt_misc/WSLInterop"
  then "wsl"
  else "linux";
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
    ./nixfiles/fonts.nix
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
    ./nixfiles/go.nix
  ];

  home.username = username;
  home.homeDirectory = homeDir;

  home.stateVersion = "23.05";

  # Default LANG
  home.language.base = "en_US.UTF-8";

  # Let home manager install and manage itself.
  programs.home-manager.enable = true;

  # PATH
  home.sessionPath = [
    "${homeDir}/bin"
    "/nix/var/nix/profiles/default/bin/nix"
  ];

  # Global variables
  home.sessionVariables = {
    _machine_os = machine_os;
  };

  # Packages to be installed
  home.packages = with pkgs; [
    git git-crypt tig
    wget zip unzip gnumake gcc pkg-config openssl
    nodejs # for lsp
    dbus gnome.gnome-keyring
    wslu
    bitwarden-cli
  ];
}
