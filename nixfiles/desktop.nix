# Desktop (non-CLI) apps and config are specified here
{ config, pkgs, fetchFromGitHub, lib, machine_os, ... }:
let
  # awesomeOverlay = (final: prev: {
  #   awesome = throw "Superseded by nix-master.";
  #   awesome-master = prev.awesome.override {
  #     version = "master-e6f5c7980862b7c3ec6c50c643b15ff2249310cc";
  #     patches = [];
  #     src = pkgs.fetchFromGitHub {
  #       owner = "AwesomeWM";
  #       repo = "awesome";
  #       rev = "e6f5c7980862b7c3ec6c50c643b15ff2249310cc";
  #       hash = lib.fakeHash;
  #     };
  #   };
  # };

  # awesomeOverlay = final: prev: {
  #   awesome-master = let rev = "e6f5c7980862b7c3ec6c50c643b15ff2249310cc";
  #   in (prev.awesome.overrideAttrs (old: {
  #     version = "master-${rev}";
  #     patches = [ ];
  #     src = prev.fetchFromGitHub {
  #       owner = "awesomeWM";
  #       repo = "awesome";
  #       inherit rev;
  #       sha256 = "afviu5b86JDWd5F12Ag81JPTu9qbXi3fAlBp9tv58fI=";
  #     };
  #     GI_TYPELIB_PATH = "${prev.playerctl}/lib/girepository-1.0:"
  #       + "${prev.upower}/lib/girepository-1.0:" + old.GI_TYPELIB_PATH;
  #   })).override { gtk3Support = true; };
  #   awesome = throw
  #     "renamed to 'awesome-master', since stable would be used here on update this error exists. For the nixpkgs version, use 'awesome-stable'";
  #   awesome-stable = prev.awesome;
  # };

  awesomeOverlay = (self: super: {
    myAwesome = super.awesome.overrideAttrs (old: rec {
      pname = "myAwesome";
      version = "master-e6f5c7980862b7c3ec6c50c643b15ff2249310cc";
      src = super.fetchFromGitHub {
        owner = "awesomeWM";
        repo = "awesome";
        rev = "16c560a568ca6f06990a0d7d4d8de3e9a77db8ec";
        sha256 = "ceHs6tbReKDW0aG1kyV6vlIjv4DGnumJgEY4Wq5wATk=";
      };
      patches = [ ];
    });
  });

  bling = pkgs.fetchFromGitHub {
    owner = "BlingCorp";
    repo = "bling";
    rev = "1f6bd0d5ef150a1801d20c69437ceff61d65fac5";
    sha256 = "0D2ck1qiA1ydLax45utJw1RhZZwhqg4KRoqgDFz4Gsg=";
  };

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
      myAwesome
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
  nixpkgs.overlays = [ awesomeOverlay ];

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
    "awesome/bling".source = bling;

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
        Exec=${pkgs.myAwesome}/bin/awesome
        TryExec=${pkgs.myAwesome}/bin/awesome
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
