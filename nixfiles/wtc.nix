{ config, pkgs, ... }:

{
    programs.fish.functions = {
        lms_switch_to = {
            argumentNames = "lms_env";
            body = ''
                ln -sf $HOME/.config/wtc/$lms_env.yml $HOME/.config/wtc/config.yml
            '';
        };
    };
}

