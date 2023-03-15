{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    python310
    python310Packages.pipx
    python310Packages.ipython
  ];

}
