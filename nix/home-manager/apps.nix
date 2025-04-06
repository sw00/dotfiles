{
  pkgs,
  config,
  lib,
  ...
}:
with pkgs; let
  # https://github.com/nix-community/home-manager/issues/3968#issuecomment-2084040097
  smonaNixgl = builtins.fetchTarball {
    url = "https://github.com/Smona/home-manager/archive/refs/heads/nixgl-compat.zip";
    sha256 = "0gfzknd0ndshvls67y4n3rqrjzma2iw0h8s3kjk6n4bxg6rixi2q";
  };
  nixGlModule = "${smonaNixgl}/modules/misc/nixgl.nix";

  cfg = config.apps;

  # install these apps always
  base = [
    bitwarden
    brave
    megasync
    alacritty
  ];

  media = [
    spotify
    calibre
  ];

  office = [
    discord
  ];

  utilities = [
    flameshot
  ];
in
  with lib; {
    imports = [
      nixGlModule
    ];

    options.apps.enable = mkEnableOption "enable desktop apps";
    options.apps.media = mkEnableOption "install media apps";
    options.apps.office = mkEnableOption "install office apps";
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
          if cfg.office
          then office
          else []
        )
        ++ (
          if cfg.utilities
          then utilities
          else []
        );
    };
  }
