{ config, pkgs, ... }:

{
  home.file.".bashrc" = {
    source = ../bashrc;
  };

  home.file.".profile" = {
    source = ../profile;
  };
}
