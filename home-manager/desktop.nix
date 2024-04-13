# Desktop (non-CLI) apps and config are specified here
{
  pkgs,
  lib,
  config,
  inputs,
  fetchFromGitHub,
  machine_os,
  nixgl,
  system,
  ...
}: let
  nixGL = import ./util/nixgl.nix {inherit pkgs config;};
  enableOnNonWSL =
    if machine_os != "wsl "
    then true
    else false;

  nerdfonts = pkgs.nerdfonts.override {fonts = ["CascadiaCode"];};

  nixpkgsUnstable = import inputs.nixpkgs-unstable {inherit system;};

  # Desktop Apps, utils, fonts, extras
  desktopPackages = with pkgs; [
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
    spotify
    (nixGL calibre)
    (nixGL nixpkgsUnstable.alacritty)
  ];

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

  linkIconThemes = lib.hm.dag.entryAfter ["linkGeneration"] ''
    $DRY_RUN_CMD ln -sf $HOME/.nix-profile/share/icons $XDG_DATA_HOME/
  '';
in {
  options.nixGLPrefix = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = ''
      Will be prepended to commands which require working OpenGL.

      This needs to be set to the right nixGL package on non-NixOS systems.
    '';
  };

  config = {
    xdg.enable = true;
    fonts.fontconfig.enable = enableOnNonWSL;

    home.packages =
      if enableOnNonWSL
      then desktopPackages
      else [];

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
      lockCmd = "sh -c 'XSECURELOCK_PASSWORD_PROMPT=kaomoji xsecurelock || kill -9 -1' ";
      inactiveInterval = 5;

      xautolock.enable = true;
    };

    # Theme
    gtk = {
      enable = true;
      theme = {name = "Adwaita";};
      cursorTheme.name = "Adwaita";
      cursorTheme.size = 16;
      iconTheme.name = "Adawaita";
    };

    # Config files
    home.file = let
      mkOutOfStoreSymlink = config.lib.file.mkOutOfStoreSymlink;
    in {
      "awesome.desktop" = {
        # should be copied to /usr/share/xsession/
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
  };
}
