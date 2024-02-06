{ home, pkgs, isWSL, ... }:
let nerdfonts = (pkgs.nerdfonts.override { fonts = [ "CascadiaCode" ]; });
in {
  # enable fonts
  fonts.fontconfig.enable = true;

  home = {
    packages = with pkgs; [ nerdfonts ];

    file = {
      ".local/share/fonts" = {
        recursive = true;
        source = "${nerdfonts}/share/fonts/truetype/NerdFonts";
      };

      ".fonts" = {
        recursive = true;
        source = "${nerdfonts}/share/fonts/truetype/NerdFonts";
      };
    };
  };

}
