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

  home.file."nvim" = {
    recursive = true;
    target = "./.config";
    source = ../config/nvim;
  };
}
