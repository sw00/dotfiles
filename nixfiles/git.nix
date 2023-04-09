{ config, pkgs, ... }:

{

  home.file.".gitconfig".source = ../gitconfig;
  home.file.".gitconfig-etckeeper".source = ../gitconfig-etckeeper;
  home.file.".gitconfig-wtc".source = ../gitconfig-wtc;

}
