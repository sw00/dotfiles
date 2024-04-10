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

  #nixgl = import <nixgl> { };
  nixgl= (pkgs.callPackage "${builtins.fetchTarball {
      url = https://github.com/guibou/nixGL/archive/d709a8abcde5b01db76ca794280745a43c8662be.tar.gz;
      sha256 = "11g411shkbxl4wxcj01dqa698hip0jg5dq2czy7q4yax4rn3cnjp";
    }}/nixGL.nix" {});

  # Desktop Apps, utils, fonts, extras
  alacrittyPkg = nixpkgsUnstable.alacritty;
  desktopPackages = with pkgs;
    [
      awesome
      acpi
      arandr
      grobi
      brightnessctl
      networkmanagerapplet
      volctl
      pavucontrol
      playerctl
      lxappearance
      elementary-xfce-icon-theme

      flameshot
      megasync
      brave
      calibre
      spotify
    ] ++ (with nixpkgsUnstable; [ alacritty ]);

  # awesome-wm-widgets
  awesomeWmWidgets = pkgs.fetchFromGitHub {
    owner = "streetturtle";
    repo = "awesome-wm-widgets";
    rev = "85fbddf6d932172acacf72253c3d96b66cd4dd57";
    hash = "sha256-VUljSRsBB5S6XCPtT+dcvM6uOcESO4nJNl3x0IJEA7E=";
    # hash = lib.fakeHash;
  };

  autorunSh = pkgs.writeShellScript "autorun.sh" ''
    run() {
        if ! pgrep -f "$1" ;
        then
            "$@"&
        fi
    }

    run grobi update
    run nm-applet
    run volctl
    run flameshot
    run megasync

    systemctl --user import-environment XDG_SESSION_ID
    systemctl --user start \
        grobi \
        xss-lock \
        xautolock-session \
        gnome-keyring
  '';

  linkIconThemes = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    $DRY_RUN_CMD ln -sf $HOME/.nix-profile/share/icons $XDG_DATA_HOME/
  '';

in {
  xdg.enable = true;
  fonts.fontconfig.enable = enableOnNonWSL;

  home.packages = if enableOnNonWSL then desktopPackages else [ ];

  services.grobi.enable = enableOnNonWSL;

  # XDG configs
  xdg.configFile = with config.lib.file; {
    # awesomewm
    "awesome/rc.lua".source = mkOutOfStoreSymlink ../config/awesome/rc.lua;
    "awesome/theme.lua".source =
      mkOutOfStoreSymlink ../config/awesome/theme.lua;
    "awesome/awesome-wm-widgets".source = awesomeWmWidgets;
    "awesome/autorun.sh".source = autorunSh;

    # grobi
    "grobi.conf".source = mkOutOfStoreSymlink ../config/grobi.conf;
  };

  # Lock screen
  services.screen-locker = {
    enable = enableOnNonWSL;
    lockCmd =
      "sh -c 'XSECURELOCK_PASSWORD_PROMPT=kaomoji xsecurelock || kill -9 -1' ";
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

  xdg.desktopEntries.Calibre = {
    name = "Calibre";
    exec =
      "${nixgl.auto.nixGLDefault}/bin/nixGL ${pkgs.calibre}/bin/calibre";
    icon = "calibre-gui";
    categories = [ "Office" ];
    startupNotify = true;
  };

  # Theme
  gtk = {
    enable = true;
    theme = { name = "Adwaita"; };
    cursorTheme.name = "Adwaita";
    cursorTheme.size = 16;
    iconTheme.name = "Adawaita";
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

    ".Xmodmap".text = ''
      clear lock
      clear control
      keycode 66 = Control_L
      add control = Control_L Control_R
    '';

  };

  home.activation.linkIconThemes = linkIconThemes;
}
