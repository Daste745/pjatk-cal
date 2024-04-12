{
  outputs = {
    self,
    nixpkgs,
  }: let
    forEachSystem = f:
      nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ] (system: f nixpkgs.legacyPackages.${system});
  in {
    devShells = forEachSystem (pkgs: {
      default = pkgs.mkShell {
        packages = with pkgs; [gleam erlang_26 rebar3];
      };
    });

    packages = forEachSystem (pkgs: let
      # TODO: Abstract all this mess into a gleam-nix library or something
      hexUrl = "https://repo.hex.pm";
      gleamManifest = builtins.fromTOML (builtins.readFile ./manifest.toml);
      gleamDeps =
        map (pkg: {
          inherit (pkg) name;
          path = pkgs.fetchurl {
            url = "${hexUrl}/tarballs/${pkg.name}-${pkg.version}.tar";
            hash = "sha256:${pkg.outer_checksum}";
          };
        })
        gleamManifest.packages;
      gleamPackagesToml = (pkgs.formats.toml {}).generate "packages.toml" {
        packages = pkgs.lib.listToAttrs (map
          (pkg: pkgs.lib.nameValuePair pkg.name pkg.version)
          gleamManifest.packages);
      };
      gleamPackageDir = pkgs.runCommandNoCC "pjatk-cal-deps" {} (''
          mkdir -p "$out"
          cp ${pkgs.lib.escapeShellArg gleamPackagesToml} "$out/packages.toml"
        ''
        + pkgs.lib.concatMapStringsSep "\n" ({
          name,
          path,
        }: ''
          cd $(mktemp -d)
          tar xf ${pkgs.lib.escapeShellArg path}
          CONTENTS=$(readlink -f contents.tar.gz)
          PKG_DIR="$out/"${pkgs.lib.escapeShellArg name}
          mkdir -p "$PKG_DIR"
          cd "$PKG_DIR"
          tar xf "$CONTENTS"
        '')
        gleamDeps);
    in rec {
      pjatk-cal = pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "pjatk-cal";
        version = "unstable-20240412";
        strictDeps = true;
        nativeBuildInputs = with pkgs; [gleam erlang_26 rebar3 makeWrapper];
        src = ./.;
        configurePhase = ''
          runHook preConfigure

          mkdir -p build/packages
          cp -r ${pkgs.lib.escapeShellArg gleamPackageDir}/* build/packages/
          chmod -R +w build
          echo baz

          runHook postConfigure
        '';
        buildPhase = ''
          runHook preBuild

          gleam export erlang-shipment

          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall

          SHIPMENT_DIR="$out/share/"${pkgs.lib.escapeShellArg finalAttrs.pname}
          mkdir -p "$out/bin" "$SHIPMENT_DIR"
          cp -r build/erlang-shipment/* "$SHIPMENT_DIR/"
          makeWrapper ${pkgs.lib.escapeShellArg pkgs.stdenvNoCC.shell} \
            "$out/bin/"${pkgs.lib.escapeShellArg finalAttrs.pname} \
            --add-flags "$SHIPMENT_DIR/entrypoint.sh" \
            --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.erlang_26]}

          runHook postInstall
        '';
        meta.mainProgram = finalAttrs.pname;
      });
      container = pkgs.dockerTools.buildImage {
        name = "pjatk-container";
        config.Cmd = [(pkgs.lib.getExe pjatk-cal) "run"];
      };
    });

    formatter = forEachSystem (pkgs: pkgs.alejandra);
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
}
