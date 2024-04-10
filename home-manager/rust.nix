{ config, pkgs, lib, ... }:
let defaultToolchain = "stable";
in with pkgs; {
  home.packages = [ rustup ];
  home.activation.initRustToolchain =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${rustup}/bin/rustup default ${defaultToolchain}
    '';
}
