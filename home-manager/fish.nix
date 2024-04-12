{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.fish = {
    enable = true;

    shellInit = ''
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
        name = "foreign-env";
        src = pkgs.fishPlugins.foreign-env.src;
      }
      {
        name = "fzf";
        src = pkgs.fishPlugins.fzf-fish.src;
      }
      {
        name = "pure";
        src = pkgs.fishPlugins.pure.src;
      }
      {
        name = "sdkman-for-fish";
        src = pkgs.fishPlugins.sdkman-for-fish.src;
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
        name = "pbcopy";
        src = pkgs.fetchFromGitHub {
          owner = "oh-my-fish";
          repo = "plugin-pbcopy";
          rev = "e8d78bb01f66246f7996a4012655b8ddbad777c2";
          sha256 = "B6/0tNk5lb+1nup1dfXhPD2S5PURZyFd8nJJF6shvq4=";
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
