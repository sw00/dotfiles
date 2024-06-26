{
  pkgs,
  config,
  ...
}: {
  programs.gpg.enable = true;
  programs.gpg.settings = {
    keyid-format = "LONG";
    with-subkey-fingerprint = true;
    with-keygrip = true;
  };

  services.gpg-agent = {
    enable =
      if pkgs.stdenv.isDarwin
      then false
      else true;
    enableFishIntegration = true;
    enableSshSupport = true;
    defaultCacheTtlSsh = 300; # 5min
    enableExtraSocket = true; # for agent forwarding
    pinentryFlavor = "qt";
  };

  programs.fish.shellInit = ''
    set -x GPG_TTY (tty)
    gpg-connect-agent updatestartuptty /bye >/dev/null
  '';
}
