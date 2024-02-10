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

  alacrittyPkg = nixpkgsUnstable.alacritty;

  nixgl = import <nixgl> { };

in {
  xdg.enable = true;
  fonts.fontconfig.enable = enableOnNonWSL;

  # Desktop Apps, fonts, extras
  home.packages = [ alacrittyPkg pkgs.awesome ];

  # AwesomeWM config
  xdg.configFile."rc.lua".source =
    config.lib.file.mkOutOfStoreSymlink ../config/awesome/rc.lua;

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
        #!/usr/bin/env bash
        ${nixgl.auto.nixGLDefault}/bin/nixGL ${alacrittyPkg}/bin/alacritty
      '';
    };

    ".alacritty.toml".source =
      mkOutOfStoreSymlink ../config/alacritty/alacritty.toml;

    ".xinitrc" = {
      text = ''
        exec ${pkgs.awesome}/bin/awesome
      '';
      executable = true;
    };

    ".Xsession" = {
      text = ''
        exec ${pkgs.awesome}/bin/awesome
      '';
      executable = true;
    };

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
