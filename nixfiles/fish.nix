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

        # Be sure your x server is running!!!
        set -x DISPLAY (cat /etc/resolv.conf | grep nameserver | awk '{print $2}'):0

        pgrep dbus-daemon > /dev/null

        if test $status -eq 1
        dbus-launch --sh-syntax | read --line bus_address ignored bus_pid bus_windowid

        set -Ux DBUS_SESSION_BUS_ADDRESS (string match -r "'(.*)'" $bus_address)[2]
        set -Ux DBUS_SESSION_BUS_ID (string match -r "=(.*);" $bus_pid)[2]
        set -Ux DBUS_SESSION_BUS_WINDOWID (string match -r "=(.*);" $bus_windowid)[2]
        end

        # pgrep limited to 15 chars, so truncate `daemon`
        pgrep -f gnome-keyring-d > /dev/null

        if test $status -eq 1
        gnome-keyring-daemon | read --line gnome_keyring_control ssh_auth_sock

        set -Ux GNOME_KEYRING_CONTROL (string split -m 1 = $gnome_keyring_control)[2]
        set -Ux SSH_AUTH_SOCK (string split -m 1 = $ssh_auth_sock)[2]
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
          sha256 = "RC4ZiuwqnaBUzsxt0jSQa13w57JPUtT3MfU1Yf1UM+Y=";
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
