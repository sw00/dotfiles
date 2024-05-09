{
  pkgs,
  config,
  lib,
  ...
}: {
  # python
  home.packages = with pkgs; [
    # common deps
    wget
    zip
    unzip
    gnumake
    gcc
    pkg-config
    openssl

    nodejs # for lsp

    # git
    git
    git-crypt
    tig

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

  # git configs
  home.file.".gitconfig".source = ../gitconfig;
  home.file.".gitconfig-etckeeper".source = ../gitconfig-etckeeper;

  # aliases
  programs.fish.shellAbbrs = {ipy = "ipython";};

  # bootstrap rust
  home.activation.initRustToolchain = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${pkgs.rustup}/bin/rustup default stable
  '';
}
