{ config, pkgs, ... }:

{
  home.sessionVariables = {
    BROWSER = "explorer.exe"; # WSL
    VAGRANT_WSL_ENABLE_WINDOWS_ACCESS = "1"; # more WSL + vagrant
  };

  home.packages = with pkgs; [
    tree
    fzf
    ripgrep
    fd
    bat
    jq
    python3Packages.howdoi
    cheat
    inotify-tools
    xsel
    htop
    asdf-vm
    nixfmt
  ];

  programs.autojump = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.fish = {
    shellInit = "\n      fish_add_path ~/.asdf/shims\n    ";

    shellAbbrs = { doco = "docker compose"; };

    functions = {
      yq = {
        description = "The yaml query tool (Golang version).";
        body = "nix run nixpkgs#yq -- $argv";
      };

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
