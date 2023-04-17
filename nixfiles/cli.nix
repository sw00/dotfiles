{ config, pkgs, ... }:

{
  home.sessionVariables = {
    BROWSER = "wslview";
  };

  programs.fish.functions = {
    jq = {
      description = "The json query tool.";
      body = "nix-shell -p jq --run \"jq $argv\"";
    };

    yq = {
      description = "The yaml query tool (Golang version).";
      body = "nix-shell -p jq-go --run \"jq $argv\"";
    };

    howdoi = {
      description = "Ask the internet how to do <query> using the `howdoi` tool.";
      body = "nix-shell -p python310Packages.howdoi --run \"howdoi $argv\"";
    };

    cheat = {
      description = "Print a cheatsheet for a command via the `cheat` tool.";
      body = "nix-shell -p cheat --run \"cheat $argv\"";
    };

    lrnx = {
      argumentNames = "language";
      description = "Open learnxinyminutes.com for <language>.";
      body = "$BROWSER \"https://learnxinyminutes.com/docs/$language\"";
    };

    pgcli = {
      description = "Postgres DB command line client with autocompletion.";
      body = "nix-shell -p pgcli --run \"pgcli $argv\"";
    };

    mycli = {
      description = "MySQL command line client with autocompletion.";
      body = "nix-shell -p mycli --run \"mycli $argv\"";
    };

    lazydocker = {
      description = "TUI for docker.";
      body = "nix-shell -p lazydocker --run \"lazydocker $argv\"";
    };

    tig = {
      description = "TUI for git.";
      body = "nix-shell -p tig --run \"tig $argv\"";
    };

    ranger = {
      description = "Command-line file manager with Vim bindings.";
      body = "nix-shell -p ranger --run \"ranger $argv\"";
    };
  };
}
