{ config, pkgs, ... }:

{
  home.file.".bashrc" = {
    source = ../bashrc;
  };

  home.file.".profile" = {
    source = ../profile;
  };

  home.file.".ssh" = {
    source = ../ssh;
    recursive = true;
  };

  # specific files
  home.file.".netrc".source = ../netrc;
}
