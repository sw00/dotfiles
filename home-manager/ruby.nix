{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [ruby_3_2];
}
