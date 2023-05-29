{ config, pkgs, ... }:

{
  home.file = {
    ".profile" = {
      source = ../profile;
    };

    ".ssh" = {
      source = ../ssh;
      recursive = true;
    };

    # specific files
    ".netrc".source = ../secrets/netrc;

    ".erdtreerc".text = '' 
      --icons
      --suppress-size
      --level 1
    '';
  };
}
