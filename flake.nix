{
  description = "tsuchiya's Nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, ... }:
    let
      mkHost = import ./lib/mkHost.nix { inherit inputs; };

      privateHostsDir = ./private/hosts;

      hostEntries =
        if builtins.pathExists privateHostsDir
        then
          let
            raw = builtins.readDir privateHostsDir;
            dirs = builtins.filter (n: raw.${n} == "directory") (builtins.attrNames raw);
          in
            map (name: {
              inherit name;
              path = privateHostsDir + "/${name}";
              meta = import (privateHostsDir + "/${name}/default.nix");
            }) dirs
        else [];

      linuxHosts = builtins.filter (h: h.meta.kind == "linux") hostEntries;
      darwinHosts = builtins.filter (h: h.meta.kind == "darwin") hostEntries;
    in {
      homeConfigurations = builtins.listToAttrs (map (h: {
        name = "${h.meta.username}@${h.name}";
        value = mkHost.mkLinuxHost h.path;
      }) linuxHosts);

      darwinConfigurations = builtins.listToAttrs (map (h: {
        name = h.name;
        value = mkHost.mkDarwinHost h.path;
      }) darwinHosts);
    };
}
