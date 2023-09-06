{ config, pkgs, lib, ... }:

{
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
        gnome-keyring-daemon 2&> /dev/null | read --line gnome_keyring_control ssh_auth_sock

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
      { name = "foreign-env"; src=pkgs.fishPlugins.foreign-env.src; }
      { name = "fzf"; src = pkgs.fishPlugins.fzf-fish.src; }
      { name = "pure"; src = pkgs.fishPlugins.pure.src; }
      { name = "sdkman-for-fish"; src = pkgs.fishPlugins.sdkman-for-fish.src; }

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
