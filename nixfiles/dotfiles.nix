{ config, pkgs, lib, ... }:

{
  home.activation = let
    entryAfter = lib.hm.dag.entryAfter;
    toPath = builtins.toPath;
  in {
    cpSshKeys = entryAfter [ "linkGeneration" ] ''
      $DRY_RUN_CMD cp -rf $VERBOSE_ARG \
        ${toPath ../secrets/ssh}/*rsa* $HOME/.ssh/
    '';
    chmodSshKeys = entryAfter [ "cpSshKeys" ] ''
      $DRY_RUN_CMD chmod $VERBOSE_ARG 0600 ~/.ssh/*_rsa
    '';
    mkSshMultiplexDir = entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p $VERBOSE_ARG $HOME/.ssh/multiplex
    '';
  };

  home.file = let mkOutOfStoreSymlink = config.lib.file.mkOutOfStoreSymlink;
  in {
    ".profile" = { source = ../profile; };

    # ssh configs
    ".ssh/config.d".source = mkOutOfStoreSymlink ../secrets/ssh/config.d;
    ".ssh/config".source = mkOutOfStoreSymlink ../secrets/ssh/config;

    # specific files
    ".netrc".source = mkOutOfStoreSymlink ../secrets/netrc;

    ".erdtreerc".text = ''
      --icons
      --suppress-size
      --level 1
    '';

  };
}
