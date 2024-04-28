{
  pkgs,
  config,
  lib,
  ...
}: {
  # python
  home.packages = with pkgs; [
    # python
    pipenv
    python311
    python311Packages.pip
    python311Packages.pipx
    python311Packages.ipython
    python311Packages.ipykernel
    python311Packages.libtmux
    python311Packages.pynvim

    # ruby
    ruby_3_2

    # rust
    rustup

    # java
    jdk
    maven
    jetbrains.idea-community
  ];

  programs.fish.shellAbbrs = {ipy = "ipython";};

  home.activation.initRustToolchain = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${pkgs.rustup}/bin/rustup default stable
  '';
}
