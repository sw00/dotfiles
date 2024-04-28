{
  config,
  pkgs,
  username,
  ...
}: let
  homeDir = "/home/${username}";

  machine_os =
    if builtins.pathExists "/proc/sys/fs/binfmt_misc/WSLInterop"
    then "wsl"
    else "linux";
in {
  # Propagate some values to submodules
  _module.args = {inherit machine_os;};

  # Assume non-NixOS Linux:
  targets.genericLinux.enable = true;

  # Enable nix experimental features
  xdg.configFile."nix.conf" = {
    target = "./nix";
    source = ../config/nix;
  };

  imports = [
    ./desktop
    ./fonts.nix
    ./dotfiles.nix
    ./gpg.nix
    ./fish.nix
    ./cli.nix
    ./tmux.nix
    ./neovim.nix
    ./git.nix
    ./programming.nix
    # ./nixfiles/java.nix
  ];

  home.username = username;
  home.homeDirectory = homeDir;

  home.stateVersion = "23.11";

  # Default LANG
  home.language.base = "en_US.UTF-8";

  # Let home manager install and manage itself.
  programs.home-manager.enable = true;

  # PATH
  home.sessionPath = [
    "${homeDir}/bin"
    "${homeDir}/.local/bin"
    "/nix/var/nix/profiles/default/bin/nix"
  ];

  # Global variables
  home.sessionVariables = {_machine_os = machine_os;};

  # Packages to be installed
  home.packages = with pkgs; [
    git
    git-crypt
    tig
    wget
    zip
    unzip
    gnumake
    gcc
    pkg-config
    openssl
    nodejs # for lsp
    bitwarden-cli
  ];

  # Keyring service
  services.gnome-keyring.enable = true;
}
