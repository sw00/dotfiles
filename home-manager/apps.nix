{
  pkgs,
  config,
  lib,
  ...
}:
with pkgs; let
  cfg = config.apps;

  # install these apps always
  base = [
    bitwarden
    brave
    megasync
  ];

  media = [
    spotify
    calibre
  ];

  utilities = [
    flameshot
  ];
in
  with lib; {
    options.apps.enable = mkEnableOption "enable desktop apps";
    options.apps.media = mkEnableOption "install media apps";
    options.apps.utilities = mkEnableOption "install utility apps";

    config = mkIf cfg.enable {
      home.packages =
        base
        ++ (
          if cfg.media
          then media
          else []
        )
        ++ (
          if cfg.utilities
          then utilities
          else []
        );
    };
  }
