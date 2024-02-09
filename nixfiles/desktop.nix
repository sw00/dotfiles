# Desktop (non-CLI) apps and config are specified here
{ config, pkgs, machine_os, ... }: {
  xdg.enable = if machine_os != "wsl" then true else false;

  # Desktop Apps
  home.packages = with pkgs; [ alacritty ];

  # Config files
  home.file = let mkOutOfStoreSymlink = config.lib.file.mkOutOfStoreSymlink;
  in {
    ".alacritty.toml".source =
      mkOutOfStoreSymlink ../config/alacritty/alacritty.toml;

    ".xprofile" = {
      text = ''
        setxkbmap -layout us -option ctrl:nocaps
      '';
      executable = true;
    };

    ".Xmodmap" = {
      text = ''
        -layout us -option ctrl:nocaps
      '';
    };
  };
}
