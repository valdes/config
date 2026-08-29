{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
  };

  outputs = { nixpkgs, home-manager, noctalia, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      keyd = import ./keyd.nix;
      keydConfig = pkgs.writeText "default.conf" ''
        [ids]
        ${builtins.concatStringsSep "\n" keyd.ids}

        ${pkgs.lib.generators.toINI { } keyd.settings}
      '';
      keydUnit = pkgs.writeText "keyd.service" ''
        [Unit]
        Description=Keyd remapping daemon
        Documentation=man:keyd(1)
        After=local-fs.target

        [Service]
        Type=simple
        ExecStart=${pkgs.keyd}/bin/keyd
        ExecReload=${pkgs.keyd}/bin/keyd reload
        Restart=always
        RuntimeDirectory=keyd

        [Install]
        WantedBy=multi-user.target
      '';
      keydSystem = pkgs.runCommand "keyd-system" {
        nativeBuildInputs = [ pkgs.keyd ];
      } ''
        keyd check ${keydConfig}
        mkdir -p "$out/bin" "$out/etc/keyd" "$out/lib/systemd/system"
        ln -s ${pkgs.keyd}/bin/keyd "$out/bin/keyd"
        ln -s ${keydConfig} "$out/etc/keyd/default.conf"
        ln -s ${keydUnit} "$out/lib/systemd/system/keyd.service"
      '';
    in
    {
      packages.${system}.keyd-system = keydSystem;

      homeConfigurations.vals = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ noctalia.homeModules.default ./home.nix ];
      };
    };
}
