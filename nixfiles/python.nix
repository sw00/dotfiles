{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    pipenv
    python310
    python310Packages.pip
    python310Packages.pipx
    python310Packages.ipython
    python310Packages.ipykernel
    python310Packages.libtmux
    python310Packages.pynvim
  ];

  programs.fish.shellAbbrs = {
    ipy = "ipython";
  };

}
