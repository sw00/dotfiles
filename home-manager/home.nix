{
  config,
  pkgs,
  inputs,
  username,
  ...
}: let
  homeDir = "/${
    if pkgs.stdenv.isDarwin
    then "Users"
    else "home"
  }/${username}";

  machine_os =
    if builtins.pathExists "/proc/sys/fs/binfmt_misc/WSLInterop"
    then "wsl"
    else "linux";
in {
  # Propagate some values to submodules
  _module.args = {inherit machine_os;};

  # Enable nix experimental features
  xdg.configFile."nix.conf" = {
    target = "./nix";
    source = ../config/nix;
  };

  imports = [
    ./apps.nix
    ./desktop
    ./fonts.nix
    ./dotfiles.nix
    ./gpg.nix
    ./fish.nix
    ./cli.nix
    ./tmux.nix
    ./neovim.nix
    ./programming.nix
    ./apps.nix
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
}
