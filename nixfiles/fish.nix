{ config, pkgs, ... }:

{
  programs.fish = {
    enable = true;

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

  home.file.".config/fish/conf.d/profile.fish".source = ../config/fish/config.fish;
}
