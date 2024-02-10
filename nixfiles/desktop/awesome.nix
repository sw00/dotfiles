{ pkgs, config, machine_os, ... }:
let
  awesomeConfig = builtins.readFile ../../config/awesome/rc.lua;
  enableOnNonWSL = if machine_os != "wsl " then true else false;
in if enableOnNonWSL then { # only apply this module if not WSL
  home.packages = with pkgs; [ awesome ];

} else
  { } # noop
