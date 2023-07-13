{ config, pkgs, ... }:

{
  home.sessionVariables = {
    BROWSER = "explorer.exe"; # WSL
  };

  home.packages = with pkgs; [
    fzf ripgrep fd autojump bat
    howdoi cheat
    inotify-tools xsel htop
    asdf-vm
  ];

  programs.fish = {
    shellAbbrs = {
      doco = "docker compose";
    };

    functions = {
      jq = {
        description = "The json query tool.";
        body = "nix run nixpkgs#jq -- $argv";
      };

      yq = {
        description = "The yaml query tool (Golang version).";
        body = "nix run nixpkgs#yq -- $argv";
      };

      lrnx = {
        argumentNames = "language";
        description = "Open learnxinyminutes.com for <language>.";
        body = "$BROWSER \"https://learnxinyminutes.com/docs/$language\"";
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
