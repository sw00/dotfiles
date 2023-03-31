{ config, pkgs, ... }:
let pkgs = import (builtins.fetchTarball {
            url = "https://github.com/NixOS/nixpkgs/archive/05ae8b52071ff158a4d3c7036e13a2e932b2549b.tar.gz";
            }) {};

myPkg = pkgs.jdk;
in

{
        home.packages = with pkgs; [
        jdk
        maven
        jetbrains.idea-community
        ];
}

