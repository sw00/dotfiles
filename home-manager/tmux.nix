{
  config,
  pkgs,
  ...
}: let
  ipAddressScript = pkgs.writeShellScript "ip_addresses" ''
    OS=$(uname -a)

    if [[ $OS == Linux* ]]; then
      if [[ $OS == *microsoft* ]]; then
        HOST=$(powershell.exe -Command "(ipconfig.exe) -Match 'IPv4'" | tr -s '\n\r' '\n' | awk '!/172(\.[0-9]+){3}/{ print $NF }')
        WSL_VM=$(ip a | awk '/inet.*([0-9]+\.)/{ print $2 }' | tail -1)
        echo "[$HOST] [$WSL_VM]"
      else
        ip address | awk '/inet.*([0-9]+\.)/{ print "[" $2 "] " }' | grep -vE '127|172'
      fi
    elif [[ $OS == "Darwin" ]]; then
      ifconfig | awk '/inet.*([0-9]+\.)/{ print "[" $2 "] " }' | tail -1
    fi
  '';

  wifiStatusScript = pkgs.writeShellScript "wifi_status" ''
    if grep -qEi '(microsoft|wsl)' /proc/version; then
      pwsh.exe -Command "(netsh wlan show interfaces) -Match '([^B]SSID|Signal|Receive|Transmit)'" \
        | tr -s '\r\n' ';' \
        | sed -rn 's#.*:\s(.*);.*:\s(.*);.*:\s(.*);.*:\s(.*);#"\1" D:\2 U:\3 S:\4#p'
    else
        iwconfig_output=$(iwconfig 2>&1)

        essid=$(echo "$iwconfig_output" | grep -oP 'ESSID:"\K([^"]+)')
        bit_rate=$(echo "$iwconfig_output" | grep -oP 'Bit Rate=\K[^ ]+' | cut -d' ' -f1)
        link_quality=$(echo "$iwconfig_output" | grep -oP 'Link Quality=\K[^ ]+' | cut -d' ' -f1)
        signal_level=$(echo "$iwconfig_output" | grep -oP 'Signal level=\K[^ ]+' | cut -d' ' -f1)

        echo "\"$essid\" D:$bit_rate Q:$link_quality S:$signal_level dBm"
    fi
  '';
in {
  home.packages = with pkgs; [tmux-sessionizer];

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
      {
        plugin = fingers;
        extraConfig = ''set -g @fingers-backdrop-style "dim"'';
      }
    ];

    extraConfig = ''
      set -ag terminal-overrides ',alacritty:RGB,gnome*:RGB,*:RGB'

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

      set -g status-right "#(${wifiStatusScript}) | #(${ipAddressScript}) | %b %d %R "
      set -g status-interval 20

      bind-key C-o display-popup -E "tms"
      bind-key C-j display-popup -E "tms switch"
      bind-key C-x display-popup -E "tms kill"
    '';
  };
}
