{ config, pkgs, ... }:

{
  programs.neovim = {
    enable              = true;
    defaultEditor       = true;
    viAlias             = true;
    vimAlias            = true;
    vimdiffAlias        = true;
    withPython3         = true;
  };

  xdg.configFile."nvim" = {
    recursive = true;
    source = ../config/nvim;
  };
}
