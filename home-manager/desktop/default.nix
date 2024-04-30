# Desktop (non-CLI) apps and config are specified here
{
  pkgs,
  lib,
  config,
  ...
}: let
  # Desktop Apps, utils, fonts, extras
  desktopPackages = with pkgs; [
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
  ];

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
    $DRY_RUN_CMD ln -sf $HOME/.nix-profile/share/icons $HOME/.local/share
  '';

in {
  options.desktop.enable = lib.mkEnableOption "enable desktop environment";

  config = lib.mkIf config.desktop.enable {
    xdg.enable = true;
    fonts.fontconfig.enable = true;
    services.grobi.enable = true;

    home.packages = desktopPackages;

    xdg.configFile = with config.lib.file; {
      # grobi
      "grobi.conf".source = mkOutOfStoreSymlink ../config/grobi.conf;
    };

    # Lock screen
    services.screen-locker = {
      enable = true;
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

    home.activation.linkIconThemes = linkIconThemes;
  };
}
