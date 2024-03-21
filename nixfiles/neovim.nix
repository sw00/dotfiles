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

  xdg.configFile.nvim-colors = {
    source = config.lib.file.mkOutOfStoreSymlink ../config/nvim/colors;
    recursive = true;
    target = "nvim/colors";
  };

  xdg.configFile.nvim-lua = {
    source = config.lib.file.mkOutOfStoreSymlink ../config/nvim/lua;
    recursive = true;
    target = "nvim/lua";
  };

}
