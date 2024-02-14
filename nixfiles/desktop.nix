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
  desktopPackages = with pkgs;
    [
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
    ] ++ (with nixpkgsUnstable; [ alacritty ]);

  # awesome-wm-widgets
  awesomeWmWidgets = pkgs.fetchFromGitHub {
    owner = "streetturtle";
    repo = "awesome-wm-widgets";
    rev = "85fbddf6d932172acacf72253c3d96b66cd4dd57";
    hash = "sha256-VUljSRsBB5S6XCPtT+dcvM6uOcESO4nJNl3x0IJEA7E=";
    # hash = lib.fakeHash;
  };

in {
  xdg.enable = true;
  fonts.fontconfig.enable = enableOnNonWSL;

  home.packages = if enableOnNonWSL then desktopPackages else [ ];

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
  services.screen-locker = {
    enable = enableOnNonWSL;
    lockCmd = "sh -c 'XSECURELOCK_PASSWORD_PROMPT=kaomoji xsecurelock || kill -9 -1' ";
    inactiveInterval = 5;

    xautolock.enable = true;
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

    ".alacritty.toml".source =
      mkOutOfStoreSymlink ../config/alacritty/alacritty.toml;

    ".xprofile" = {
      text = ''
        setxkbmap -layout us -option ctrl:nocaps

        systemctl --user import-environment XDG_SESSION_ID
        systemctl --user start xss-lock
        systemctl --user start xautolock-session
        systemctl --user start gnome-keyring

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
