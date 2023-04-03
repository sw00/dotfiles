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
    ./nixfiles/gpg.nix
    ./nixfiles/fish.nix
    ./nixfiles/tmux.nix
    ./nixfiles/neovim.nix
    ./nixfiles/git.nix
    ./nixfiles/python.nix
    ./nixfiles/rust.nix
    ./nixfiles/java.nix
    ./nixfiles/wtc.nix
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
    git git-crypt gnupg tig
    fzf ripgrep fd autojump xsel
    wget unzip gnumake gcc pkg-config openssl
    nodejs # for lsp
    dbus gnome.gnome-keyring
    wslu
    bitwarden-cli
    jq yq
    cheat
  ];
}
