{ config, pkgs, ... }:

{
  home.packages = with pkgs; [ doctl terraform ];

  programs.fish.functions = {
    lms_switch_to = {
      argumentNames = "lms_env";
      body = ''
        ln -sf $HOME/.config/wtc/$lms_env.yml $HOME/.config/wtc/config.yml
      '';
    };
  };

  programs.fish.shellAbbrs = {
    wlms = "wtc-lms";
    wadmin = "wtc-admin-cli";
    tf = "terraform";
  };

  xdg.configFile."prod.yml" = {
    target = "./wtc/prod.yml";
    source = ../secrets/wtc/prod.yml;
  };

  xdg.configFile."tvet.yml" = {
    target = "./wtc/tvet.yml";
    source = ../secrets/wtc/tvet.yml;
  };

  xdg.configFile."bootcamp.yml" = {
    target = "./wtc/bootcamp.yml";
    source = ../secrets/wtc/bootcamp.yml;
  };

  xdg.configFile."local.yml" = {
    target = "./wtc/local.yml";
    source = ../secrets/wtc/local.yml;
  };
}

