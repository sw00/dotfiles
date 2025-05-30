{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.devops;
in {
  options = {
    devops.enable = lib.mkEnableOption "devops tools and shortcuts";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [argocd kubectx azure-cli];

    programs.fish.shellAbbrs = {
      kx = "kubectx";
      kn = "kubens";
      kc = "kubectl";
      flyl = "fly -t lelapa";
    };
  };
}
