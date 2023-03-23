{ pkgs, config, ... }:

{
    services.gpg-agent = {
        enable = true;
        enableFishIntegration = true;
        pinentryFlavor = "curses";
    };
}
