{ config, pkgs, ... }:

{
  home.file.".bashrc" = {
    source = ../bashrc;
  };

  home.file.".profile" = {
    source = ../profile;
  };

  home.file.".tmux.conf".source = ../tmux.conf;

  home.file.".ssh" = {
    source = ../ssh;
    recursive = true;
  };
}
