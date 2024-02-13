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
    acpi
    arandr
    autorandr
    brightnessctl
    networkmanagerapplet
    pavucontrol
    playerctl
    lxappearance

    megasync
  ];

  # awesomewm config
  awesomeWmConfig = /home/sett/config/awesome;
  awesomeWmWidgets = pkgs.fetchFromGitHub {
    owner = "streetturtle";
    repo = "awesome-wm-widgets";
    rev = "85fbddf6d932172acacf72253c3d96b66cd4dd57";
    hash = "sha256-VUljSRsBB5S6XCPtT+dcvM6uOcESO4nJNl3x0IJEA7E=";
    # hash = lib.fakeHash;
  };

  awesomeXdgConfig = pkgs.symlinkJoin {
    name = "awesomewm-xdg-config";
    paths = [ awesomeWmConfig awesomeWmWidgets ];
  };

in {
  xdg.enable = true;
  fonts.fontconfig.enable = enableOnNonWSL;

  home.packages = if enableOnNonWSL then desktopPackages else [];

  # Services
  services.autorandr.enable = enableOnNonWSL;

  # AwesomeWM config
  xdg.configFile = with config.lib.file; {
    "awesome/rc.lua".source = mkOutOfStoreSymlink ../config/awesome/rc.lua;
    "awesome/keys".source = mkOutOfStoreSymlink ../config/awesome/keys;
    "awesome/ui".source = mkOutOfStoreSymlink ../config/awesome/ui;
    "awesome/awesome-wm-widgets".source = awesomeWmWidgets;
  };

  # Lock screen
  services.betterlockscreen = {
    enable = enableOnNonWSL;
    inactiveInterval = 5;
    arguments = [
      "--color"
      "#00838F" # some shade of teal
      "--off"
      "120" # turn off screen after 2min
    ];
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
        xinput set-prop 'Synaptics TM3512-010' 'libinput Tapping Enabled' 1
        xinput set-prop 'Synaptics TM3512-010' 'libinput Scrolling Pixel Distance' 10

        megasync &
        nm-applet &
      '';
      executable = true;
    };

    ".Xresources" = {
      text = ''
        Xcursor.size: 16
      '';
    };
  };

}
