{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [jdk maven jetbrains.idea-community];
}
