{ config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    # defaultEditor       = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    withPython3 = true;

    extraConfig = ''
      :luafile ~/.config/nvim/lua/init.lua
    '';
    plugins = with pkgs.vimPlugins; [ packer-nvim mini-nvim nvim-tree-lua ];
  };

  home.sessionVariables = { EDITOR = "nvim"; };

  xdg.configFile.nvim = {
    source = ../config/nvim;
    recursive = true;
  };

}
