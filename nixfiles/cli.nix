{ config, pkgs, ... }:

{
  home.sessionVariables = {
    BROWSER = "wslview";
  };

  programs.fish.functions = {
    jq = {
      argumentNames = "args";
      description = "The json query tool.";
      body = "nix-shell -p jq --run \"jq $args\"";
    };

    yq = {
      argumentNames = "args";
      description = "The yaml query tool (Golang version).";
      body = "nix-shell -p jq-go --run \"jq $args\"";
    };

    howdoi = {
      argumentNames = "query";
      description = "Ask the internet how to do <query> using the `howdoi` tool.";
      body = "nix-shell -p python310Packages.howdoi --run \"howdoi $query\"";
    };

    cheat = {
      argumentNames = "query";
      description = "Print a cheatsheet for a command via the `cheat` tool.";
      body = "nix-shell -p cheat --run \"cheat $query\"";
    };

    lrnx = {
      argumentNames = "language";
      description = "Open learnxinyminutes.com for <language>.";
      body = "$BROWSER \"https://learnxinyminutes.com/docs/$language\"";
    };

    pgcli = {
      argumentNames = "args";
      description = "Postgres DB command line client with autocompletion.";
      body = "nix-shell -p pgcli --run \"pgcli $args\"";
    };

    mycli = {
      argumentNames = "args";
      description = "MySQL command line client with autocompletion.";
      body = "nix-shell -p mycli --run \"mycli $args\"";
    };
  };
}
