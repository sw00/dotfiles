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

    # asdf
    asdf-vm

    nodejs # for lsp

    # git
    git
    git-crypt
    git-lfs
    tig

    # python
    pipenv
    python311
    python311Packages.pip
    python311Packages.pipx
    python311Packages.ipython
    python311Packages.ipykernel

    # ruby
    ruby_3_2

    # rust
    rustup

    # java
    jdk
    maven
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
