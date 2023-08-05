{ config, pkgs, ... }:

{
  home.file.".tmux.conf".source = ../tmux.conf;

  home.file."./bin/ip_addresses" = {
    executable = true;
    text = ''
        #!/usr/bin/env fish

        switch $_machine_os
        case wsl
            set HOST (powershell.exe -Command "(ipconfig.exe) -Match 'IPv4'" | tr -s '\n\r' '\n' | awk '!/172(\.[0-9]+){3}/{ print $NF }')
            set WSL_VM (ip a | awk '/inet.*([0-9]+\.)/{ print $2 }' | tail -1)
            echo "[$HOST] [$WSL_VM]"
        case darwin
            ifconfig | awk '/inet.*([0-9]+\.)/{ print "[" $2 "] " }' | tail -1
        case '*'
            ip address | awk '/inet.*([0-9]+\.)/{ print "[" $2 "] " }' | tail -1
        end
    '';
  };

  home.file."./bin/wifi_status" = {
    executable = true;
    text = ''
        #!/usr/bin/env fish

        switch $_machine_os
        case wsl
          pwsh.exe -Command "(netsh wlan show interfaces) -Match '([^B]SSID|Signal|Receive|Transmit)'" \
            | tr -s '\r\n' ';' \
            | sed -rn 's#.*:\s(.*);.*:\s(.*);.*:\s(.*);.*:\s(.*);#"\1" D:\2 U:\3 S:\4#p'
        end
    '';
  };

}
