{
  description = "Sett's Nix flake config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Home manager
    home-manager.url = "github:nix-community/home-manager/release-23.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixgl.url = "github:nix-community/nixGL";
    nixgl.inputs.nixpkgs.follows = "nixpkgs";

    hardware.url = "github:nixos/nixos-hardware";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    darwin,
    home-manager,
    nixgl,
    ...
  } @ inputs: let
    inherit (self) outputs;

    system = "x86_64-linux";
    username = "sett";

    pkgs = import nixpkgs {
      inherit system;

      config.allowUnfree = true;
      config.allowUnfreePredicate = _: true;
    };
  in {
    # nixGL shenanigans - https://github.com/nix-community/nixGL/issues/114#issuecomment-1869662332

    # NixOS configuration entrypoint
    # Available through 'nixos-rebuild --flake .#your-hostname'
    nixosConfigurations = {
      x1c2e = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [
          ./nixos/x1c2e/configuration.nix

          # home manager as nixos module
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {inherit inputs username;};
            home-manager.users.${username} = {
              imports = [
                ./home-manager/home.nix
              ];
              desktop.enable = false;
              apps.enable = true;
              apps.media = true;
              apps.office = true;
              apps.utilities = true;
            };
          }
        ];
      };
    };

    # MacOS configuration entrypoint
    # Available through 'darwin-rebuild switch --flake .#your-hostname'
    darwinConfigurations = {
      mbpm3 = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = {inherit inputs outputs self;};
        modules = [
          {
            nixpkgs.overlays = [
              (final: prev: {
                unstable = import nixpkgs-unstable {
                  inherit system;
                  config.allowUnfree = true;
                };
              })
            ];
          }
          ./macos/mbpm3/configuration.nix
          ./macos/mbpm3/homebrew.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {inherit inputs username;};
            home-manager.users.${username} = {
              imports = [
                ./home-manager/home.nix
                ({
                  config,
                  lib,
                  ...
                }: {
                  home.file.".alacritty.toml" = lib.mkForce {
                    source = config.lib.file.mkOutOfStoreSymlink ./macos/mbpm3/alacritty.toml;
                  };

                  programs.fish.shellInit = ''
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                  '';
                })
              ];
              desktop.enable = false;
              apps.enable = false;
              devops.enable = true;
            };
          }
        ];
      };
    };
    # Expose the package set, including overlays, for convenience.
    #darwinPackages = self.darwinConfigurations."mbpm3".pkgs;

    # Standalone home-manager configuration entrypoint
    # Available through 'home-manager --flake .#your-username@your-hostname'
    homeConfigurations = {
      "sett@x1c2e" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        extraSpecialArgs = {inherit inputs outputs;};
        modules = [./home-manager/home.nix];
      };
    };
  };
}
