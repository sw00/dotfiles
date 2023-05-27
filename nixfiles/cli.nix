{ config, pkgs, ... }:

{
  home.sessionVariables = {
    BROWSER = "explorer.exe"; # WSL
  };

  home.packages = with pkgs; [
    asdf-vm
  ];

  programs.fish.functions = {
    jq = {
      description = "The json query tool.";
      body = "nix run nixpkgs#jq -- $argv";
    };

    yq = {
      description = "The yaml query tool (Golang version).";
      body = "nix run nixpkgs#yq -- $argv";
    };

    howdoi = {
      description = "Ask the internet how to do <query> using the `howdoi` tool.";
      body = "nix run nixpkgs#howdoi -- $argv";
    };

    cheat = {
      description = "Print a cheatsheet for a command via the `cheat` tool.";
      body = "nix run nixpkgs#cheat -- $argv";
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

    tig = {
      description = "TUI for git.";
      body = "nix run nixpkgs#tig -- $argv";
    };

    ranger = {
      description = "Command-line file manager with Vim bindings.";
      body = "nix run nixpkgs#ranger -- $argv";
    };
  };
}
