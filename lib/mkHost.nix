{ inputs }:
let
  inherit (inputs) nixpkgs home-manager nix-darwin;

  nixpkgsConfig = {
    config.allowUnfree = true;
    overlays = [
      (final: prev: {
        mise =
          if prev.stdenv.hostPlatform.isDarwin && prev.mise.version == "2026.6.11" then
            # mise 2026.6.11 has a Darwin-only test failure in its OCI layer
            # metadata test: the fixture expects a setuid bit that the build
            # environment reads back as a normal executable mode.
            prev.mise.overrideAttrs {
              doCheck = false;
            }
          else
            prev.mise;
      })
    ];
  };

  mkPkgs = system: import nixpkgs ({ inherit system; } // nixpkgsConfig);
in
{
  mkLinuxHost = hostDir:
    let
      meta = import (hostDir + "/default.nix");
    in
    home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs meta.system;
      extraSpecialArgs = {
        llm-agents = inputs.llm-agents.packages.${meta.system};
      };
      modules = [
        ../home/common
        ../home/linux
        (hostDir + "/home.nix")
        {
          home.username = meta.username;
          home.homeDirectory = meta.homeDirectory;
          home.stateVersion = "24.11";
        }
      ];
    };

  mkDarwinHost = hostDir:
    let
      meta = import (hostDir + "/default.nix");
    in
    nix-darwin.lib.darwinSystem {
      system = meta.system;
      modules = [
        {
          nixpkgs = nixpkgsConfig;
          # Determinate Nix manages the Nix installation itself; let
          # nix-darwin stay out of `nix.*` to avoid the two clashing.
          nix.enable = false;
        }
        ../system/darwin
        home-manager.darwinModules.home-manager
        {
          users.users.${meta.username}.home = meta.homeDirectory;
          system.primaryUser = meta.username;

          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            extraSpecialArgs = {
              llm-agents = inputs.llm-agents.packages.${meta.system};
            };
            users.${meta.username} = {
              imports = [
                ../home/common
                ../home/darwin
                (hostDir + "/home.nix")
              ];
              home.username = meta.username;
              home.homeDirectory = meta.homeDirectory;
              home.stateVersion = "24.11";
            };
          };

          system.stateVersion = 5;
        }
      ];
    };
}
