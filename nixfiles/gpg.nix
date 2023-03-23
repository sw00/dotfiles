{ pkgs, config, ... }:

{
    programs.gpg.enable = true;
    programs.gpg.settings = {
        keyid-format = "LONG";
        with-subkey-fingerprint = true;
        with-keygrip = true;
    };

    services.gpg-agent = {
        enable = true;
        enableFishIntegration = true;
        pinentryFlavor = "qt";
    };
}
