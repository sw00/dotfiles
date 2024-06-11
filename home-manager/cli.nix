{
  config,
  pkgs,
  ...
}: {
  home.sessionVariables = {
    BROWSER =
      if pkgs.stdenv.isDarwin
      then "open"
      else "explorer.exe"; # WSL
    VAGRANT_WSL_ENABLE_WINDOWS_ACCESS = "1"; # more WSL + vagrant
  };

  home.packages = with pkgs; [
    tree
    fzf
    ripgrep
    fd
    bat
    jq
    yq
    # python3Packages.howdoi - broken
    cheat
    # inotify-tools - not on aarch64-darwin
    # xsel - platform specific
    htop
    # nixfmt - use alejandra
    lf
  ];

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.direnv = {
    enable = true;
  };

  programs.fish = {
    shellInit = "\n      fish_add_path ~/.asdf/shims\n    ";

    shellAbbrs = {
    doco = "docker compose";

    # gh cli
    ghce = "gh copilot explain";
    ghcs = "gh copilot suggest";
    };

    functions = {
      lrnx = {
        argumentNames = "language";
        description = "Open learnxinyminutes.com for <language>.";
        body = ''$BROWSER "https://learnxinyminutes.com/docs/$language"'';
      };

      pgcli = {
        description = "Postgres DB command line client with autocompletion.";
        body = "nix run nixpkgs#pgcli -- $argv";
      };

      mycli = {
        description = "MySQL command line client with autocompletion.";
        body = "nix run nixpkgs#mycli -- $argv";
      };

      lazydocker = {
        description = "TUI for docker.";
        body = "nix run nixpkgs#lazydocker -- $argv";
      };

      ranger = {
        description = "Command-line file manager with Vim bindings.";
        body = "nix run nixpkgs#ranger -- $argv";
      };

      slack-term = {
        description = "Terminal client for slack";
        body = "nix run nixpkgs#slack-term -- $argv";
      };
    };
  };
}
