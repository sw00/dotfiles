# Desktop (non-CLI) apps and config are specified here
{ config, pkgs, fetchFromGitHub, lib, machine_os, ... }:
let
  enableOnNonWSL = if machine_os != "wsl " then true else false;

  nerdfonts = pkgs.nerdfonts.override { fonts = [ "CascadiaCode" ]; };

  nixpkgsUnstable = (import (pkgs.fetchFromGitHub {
    owner = "NixOS";
    repo = "nixpkgs";
    rev =
      "f8e2ebd66d097614d51a56a755450d4ae1632df1"; # nixos-unstable @ 2024-02-09
    hash = "sha256-2en1kvde3cJVc3ZnTy8QeD2oKcseLFjYPLKhIGDanQ0=";
  }) { });

  nixgl = import <nixgl> { };

  # Desktop Apps, utils, fonts, extras
  alacrittyPkg = nixpkgsUnstable.alacritty;
  desktopPackages = with pkgs; [
    awesome
    arandr
    autorandr
    networkmanagerapplet
    pavucontrol
    playerctl
    lxappearance

    megasync
  ];

in {
  xdg.enable = true;
  fonts.fontconfig.enable = enableOnNonWSL;

  home.packages = desktopPackages;

  # AwesomeWM config
  xdg.configFile."awesome" = {
    source = config.lib.file.mkOutOfStoreSymlink ../config/awesome;
    target = "awesome";
  };

  # Desktop shortcuts
  xdg.desktopEntries.Alacritty = {
    name = "Alacritty";
    genericName = "Terminal";
    exec =
      "${nixgl.auto.nixGLDefault}/bin/nixGL ${alacrittyPkg}/bin/alacritty %u";
    icon = "Alacritty";
    categories = [ "System" "TerminalEmulator" ];
    startupNotify = true;
    actions = {
      newTerminal = {
        name = "New Terminal";
        exec =
          "${nixgl.auto.nixGLDefault}/bin/nixGL ${alacrittyPkg}/bin/alacritty %u";
      };
    };
  };

  # Config files
  home.file = let mkOutOfStoreSymlink = config.lib.file.mkOutOfStoreSymlink;
  in {
    "awesome.desktop" = { # should be copied to /usr/share/xsession/
      target = ".local/share/xsession/awesome.desktop";
      text = ''
        [Desktop Entry]
        Name=awesome
        Comment=Highly configurable framework window manager
        Exec=${pkgs.awesome}/bin/awesome
        TryExec=${pkgs.awesome}/bin/awesome
        Type=Application
        DesktopNames=awesome:AwesomeWM
      '';
    };

    "run-alacritty.sh" = {
      target = ".local/bin/run-alacritty.sh";
      executable = true;
      text = ''
        ${nixgl.auto.nixGLDefault}/bin/nixGL ${alacrittyPkg}/bin/alacritty $@
      '';
    };

    ".alacritty.toml".source =
      mkOutOfStoreSymlink ../config/alacritty/alacritty.toml;

    ".xprofile" = {
      text = ''
        setxkbmap -layout us -option ctrl:nocaps

        xinput set-prop 'Synaptics TM3512-010' 'libinput Natural Scrolling Enabled' 1
        xinput set-prop 'Synaptics TM3512-010' 'libinput Accel Speed' 0.42
        xinput set-prop 'Synaptics TM3512-010' 'libinput Natural Scrolling Enabled' 1
        xinput set-prop 'Synaptics TM3512-010' 'libinput Scrolling Pixel Distance' 10

        nm-applet &
        megasync &
      '';
      executable = true;
    };
  };

}
