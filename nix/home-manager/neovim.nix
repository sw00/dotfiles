{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [neovim];
  home.shellAliases = {
    vi = "nvim";
    vim = "nvim";
  };

  home.sessionVariables = {EDITOR = "nvim";};

  xdg.configFile.nvim = {
    source = config.lib.file.mkOutOfStoreSymlink ../config/nvim;
    recursive = false;
  };
}
