{ inputs }:
let
  inherit (inputs) nixpkgs home-manager nix-darwin;

  nixpkgsConfig = {
    config.allowUnfree = true;
    overlays = [
      inputs.llm-agents.overlays.default
      (final: prev: {
        emacs =
          if prev.stdenv.hostPlatform.isDarwin then
            # Emacs' Nextstep sources are Objective-C files that include C
            # headers expecting C23 bool/alignment helpers. Clang does not
            # expose those names there unless the compatibility headers are
            # included explicitly.
            prev.emacs.overrideAttrs (old: {
              NIX_CFLAGS_COMPILE =
                (old.NIX_CFLAGS_COMPILE or "")
                + " -include stdbool.h -include stdalign.h";
            })
          else
            prev.emacs;
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
