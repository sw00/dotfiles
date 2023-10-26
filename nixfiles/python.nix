{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    pipenv
    python311
    python311Packages.pip
    python311Packages.pipx
    python311Packages.ipython
    python311Packages.ipykernel
    python311Packages.libtmux
    python311Packages.pynvim
  ];

  programs.fish.shellAbbrs = {
    ipy = "ipython";
  };

}
