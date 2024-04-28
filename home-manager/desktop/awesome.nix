{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.desktop.awesome;

  awesome-overlay = import ./awesome-git-overlay.nix;

  # awesome-wm-widgets
  awesomeWmWidgets = pkgs.fetchFromGitHub {
    owner = "streetturtle";
    repo = "awesome-wm-widgets";
    rev = "85fbddf6d932172acacf72253c3d96b66cd4dd57";
    hash = "sha256-VUljSRsBB5S6XCPtT+dcvM6uOcESO4nJNl3x0IJEA7E=";
    # hash = lib.fakeHash;
  };

in {
  options = {
    cfg.enable = mkEnableOption "Awesome window manager";
  };

  config = lib.mkIf config.desktop.awesome.enable {
    xsession.windowmanager.awesome = {
      enable = true;
    };

    home.packages = let
      package = {
        version = "8b1f8958b46b3e75618bc822d512bb4d449a89aa";
        src = pkgs.fetchFromGitHub {
          owner = "awesomeWM";
          repo = "awesome";
          rev = "8b1f8958b46b3e75618bc822d512bb4d449a89aa";
          fetchSubmodules = false;
          sha256 = "sha256-ZGZ53IWfQfNU8q/hKexFpb/2mJyqtK5M9t9HrXoEJCg=";
        };
        date = "2024-03-23";
      };
      extraGIPackages = with pkgs; [networkmanager upower playerctl];
    in [
      (pkgs.awesome.override {gtk3Support = true;}).overrideAttrs
      (old: {
        inherit (package) src version;

        patches = [];

        postPatch = ''
          patchShebangs tests/examples/_postprocess.lua
          patchShebangs tests/examples/_postprocess_cleanup.lua
        '';

        cmakeFlags = old.cmakeFlags ++ ["-DGENERATE_MANPAGES=OFF"];

        GI_TYPELIB_PATH = let
          mkTypeLibPath = pkg: "${pkg}/lib/girepository-1.0";
          extraGITypeLibPaths = prev.lib.forEach extraGIPackages mkTypeLibPath;
        in
          prev.lib.concatStringsSep ":" (extraGITypeLibPaths ++ [(mkTypeLibPath prev.pango.out)]);
      })
    ];

    # config files
    xdg.configFile = with config.lib.file; {
      # awesomewm
      "awesome/rc.lua".source = mkOutOfStoreSymlink ../config/awesome/rc.lua;
      "awesome/theme.lua".source =
        mkOutOfStoreSymlink ../config/awesome/theme.lua;
      "awesome/awesome-wm-widgets".source = awesomeWmWidgets;
      "awesome/autorun.sh".source = autorunSh;
    };

  };
}
