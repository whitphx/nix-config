{ inputs }:
let
  inherit (inputs) nixpkgs home-manager nix-darwin;

  mkPkgs = system: import nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [ inputs.llm-agents.overlays.default ];
  };
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
        home-manager.darwinModules.home-manager
        {
          users.users.${meta.username}.home = meta.homeDirectory;

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
