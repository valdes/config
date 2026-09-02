{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr = {
      url = "github:herdrdev/herdr/v0.8.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
  };

  outputs = { nixpkgs, home-manager, herdr, noctalia, ... }:
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
      codexbarCli = pkgs.stdenvNoCC.mkDerivation {
        pname = "codexbar-cli";
        version = "0.56.3";
        src = pkgs.fetchurl {
          url = "https://github.com/steipete/CodexBar/releases/download/v0.56.3/CodexBarCLI-v0.56.3-linux-musl-x86_64.tar.gz";
          hash = "sha256-YTYjbw8f8HJYuNTIyWTwr4uFSv+W1nCtCT6eL8c6q6M=";
        };
        sourceRoot = ".";
        installPhase = ''
          runHook preInstall
          install -Dm755 CodexBarCLI "$out/bin/CodexBarCLI"
          install -Dm644 VERSION "$out/bin/VERSION"
          ln -s CodexBarCLI "$out/bin/codexbar"
          cp -r CodexBar_CodexBarCore.bundle "$out/bin/"
          runHook postInstall
        '';
        meta.mainProgram = "codexbar";
      };
    in
    {
      packages.${system} = {
        keyd-system = keydSystem;
        codexbar-cli = codexbarCli;
      };

      homeConfigurations.vals = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          herdrPackage = herdr.packages.${system}.default;
          codexbarCliPackage = codexbarCli;
        };
        modules = [ noctalia.homeModules.default ./home.nix ];
      };
    };
}
