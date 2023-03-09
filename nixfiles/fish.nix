{ config, pkgs, ... }:

{
  programs.fish = {
    enable = true;

    shellInit = ''
        if test -e $HOME/.nix-profile/etc/profile.d/nix.sh
            fenv . $HOME/.nix-profile/etc/profile.d/nix.sh
        end

        set -xg sysinfo (uname -a)

        if string match -eiq wsl $sysinfo
            set -g _machine_os wsl
            alias psh='powershell.exe -Command '
        else if string match -eiq darwin $syinfo
            set -g _machine_os darwin
        else
            set -g _machine_os linux
        end
    '';

    functions = {
        opn = {
            body = ''
                switch $_machine_os
                case wsl
                    wslview $argv
                case '*'
                    open $argv
                end
            '';
        };

        nix_shell_info = {
            body = ''
                if test -n \"$IN_NIX_SHELL\"; echo -n \"<nix-shell> \"; end
            '';
        };
    };

    plugins = [
      {
        name = "kawasaki";
        src = pkgs.fetchFromGitHub {
          owner = "hastinbe";
          repo = "theme-kawasaki";
          rev = "v1.1.1";
          sha256 = "BdV4FtHBDBdERb9t2xQ9gQ0MiymE1ls8WNGBToZtqnE=";
        };
      }
      {
        name = "bang-bang";
        src = pkgs.fetchFromGitHub {
          owner = "oh-my-fish";
          repo = "plugin-bang-bang";
          rev = "816c66df34e1cb94a476fa6418d46206ef84e8d3";
          sha256 = "35xXBWCciXl4jJrFUUN5NhnHdzk6+gAxetPxXCv4pDc=";
        };
      }
      {
        name = "foreign-env";
        src = pkgs.fetchFromGitHub {
          owner = "oh-my-fish";
          repo = "plugin-foreign-env";
          rev = "3ee95536106c11073d6ff466c1681cde31001383";
          sha256 = "vyW/X2lLjsieMpP9Wi2bZPjReaZBkqUbkh15zOi8T4Y=";
        };
      }
      {
        name = "pbcopy";
        src = pkgs.fetchFromGitHub {
          owner = "oh-my-fish";
          repo = "plugin-pbcopy";
          rev = "e8d78bb01f66246f7996a4012655b8ddbad777c2";
          sha256 = "B6/0tNk5lb+1nup1dfXhPD2S5PURZyFd8nJJF6shvq4=";
        };
      }
      {
        name = "fzf";
        src = pkgs.fetchFromGitHub {
          owner = "jethrokuan";
          repo = "fzf";
          rev = "0.16.6";
          sha256 = "/RxsfFISqYpoaH97m+D8o4cb4zpNw5cLJITgbWIk1v0=";
        };
      }
      {
        name = "autojump";
        src = pkgs.fetchFromGitHub {
          owner = "rominf";
          repo = "omf-plugin-autojump";
          rev = "86f2aa23ae64b4de389e63c71d4ea372958685dc";
          sha256 = "PPl/TvfzlRkEctZ0vX04CUNZDNEiQSTkZMkigyw0c04=";
        };
      }
      {
        name = "git";
        src = pkgs.fetchFromGitHub {
          owner = "jhillyerd";
          repo = "plugin-git";
          rev = "v0.1";
          sha256 = "MfrRQdcj7UtIUgtqKjt4lqFLpA6YZgKjE03VaaypNzE=";
        };
      }
    ];
  };
}
