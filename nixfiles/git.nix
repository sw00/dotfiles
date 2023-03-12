{ config, pkgs, ... }:

{

  home.file.".gitconfig".source = ../gitconfig;
  home.file.".gitconfig-etckeeper".source = ../gitconfig;
  home.file.".gitconfig-wtc".source = ../gitconfig;

}
