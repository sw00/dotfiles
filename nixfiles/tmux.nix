{ config, pkgs, ... }:
let
  ipAddressScript = pkgs.writeScript "ip_addresses" ''
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

  wifiStatusScript = pkgs.writeScript "wifi_status" ''
        #!/usr/bin/env fish

        switch $_machine_os
        case wsl
          pwsh.exe -Command "(netsh wlan show interfaces) -Match '([^B]SSID|Signal|Receive|Transmit)'" \
            | tr -s '\r\n' ';' \
            | sed -rn 's#.*:\s(.*);.*:\s(.*);.*:\s(.*);.*:\s(.*);#"\1" D:\2 U:\3 S:\4#p'
        end
    '';
in

{

  programs.tmux = {
    enable = true;
    shortcut = "a";
    # prefix = "C-a";
    terminal = "tmux-256color";
    shell = "${pkgs.fish}/bin/fish";
    newSession = false;
    historyLimit = 100000;
    baseIndex = 1;
    escapeTime = 1;
    clock24 = true;
    mouse = true;
    keyMode = "vi";
    customPaneNavigationAndResize = true;
    resizeAmount = 10;
    secureSocket = false; # for wsl compatibility
    sensibleOnTop = true;

    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = mkTmuxPlugin {
          pluginName = "tmux-window-rename";
          rtpFilePath = "tmux_window_name.tmux";
          version = "19b65ef";
          src = pkgs.fetchFromGitHub {
            owner = "ofirgall";
            repo = "tmux-window-name";
            rev = "19b65efa8c37501799789194be2a99293e67c632";
            sha256 = "sha256-VHtnN9XyEv8Gbwq5bJuq8QS04opwDOTGzEcLREy6kBA=";
          };
        };
      }
      {
        plugin = resurrect;
        extraConfig = "set -g @resurrect-strategy-nvim 'session'";
      }
    ];

    extraConfig = ''
      set -sa terminal-features ',XXX:RGB'
      set -ag terminal-overrides ',*:cud1=\E[1B'

      bind R source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded..."

      bind-key C-A last-window

      bind | split-window -h -c '#{pane_current_path}'
      bind - split-window -v -c '#{pane_current_path}'

      bind-key -T copy-mode-vi v send -X begin-selection
      bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "pbcopy"
      bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "pbcopy"

      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      bind -r C-h resize-pane -L
      bind -r C-j resize-pane -D
      bind -r C-k resize-pane -U
      bind -r C-l resize-pane -R

      set -g status-position top
      set -g status-justify left
      set -g status-bg black
      set -g status-fg white

      set -g window-status-format "#[fg=white] #I:#W "
      set -g window-status-current-format "#[bg=green,fg=white] #I:#W "
      set -g window-status-style "bg=black"
      set -g window-status-last-style "bg=black,fg=green"

      set -g status-right-length 120
      set -g status-left ""

      set -g status-right "#(${wifiStatusScript}) | #(${ipAddressScript}) | %b %d %R "
      set -g status-interval 20
    '';
  };

}
