{
  description = "Agda is a dependently typed programming language / interactive theorem prover.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }: (flake-utils.lib.eachDefaultSystem (system: let
    pkgs = import nixpkgs { inherit system; overlays = [ self.overlay ]; };
  in {
    packages = {
      inherit (pkgs.haskellPackages) Agda;

      # TODO agda2-mode
    };

    defaultPackage = self.packages.${system}.Agda;

    devShell = let
      hsenv = pkgs.haskell.packages.ghc942.ghcWithPackages (p: [
        p.distributive
        p.indexed-traversable-instances
        p.comonad
        p.witherable
        p.bifunctors
        p.assoc
        p.semigroupoids
        p.these
        p.strict
        p.semialign
        p.aeson
        p.tagged
        p.time-compat
      ]);
    in
    pkgs.mkShell {
      inputsFrom = [ self.defaultPackage.${system} ];
      packages = with pkgs; [
        pkg-config
        zlib
        icu
        #haskellPackages.fix-whitespace
        hsenv
      ];
    };
  })) // {
    overlay = final: prev: {
      haskellPackages = prev.haskellPackages.override {
        overrides = self.haskellOverlay;
      };
    };

    haskellOverlay = final: prev: let
      inherit (final) callCabal2nixWithOptions;

      shortRev = builtins.substring 0 9 self.rev;

      postfix = if self ? revCount then "${toString self.revCount}_${shortRev}" else "Dirty";
    in {
      # TODO use separate evaluation system?
      Agda = callCabal2nixWithOptions "Agda" ./. "--flag enable-cluster-counting --flag optimise-heavily" ({
        mkDerivation = args: final.mkDerivation (args // {
          version = "${args.version}-pre${postfix}";

          postInstall = "$out/bin/agda-mode compile";

          # TODO Make check phase work
          # At least requires:
          #   Setting AGDA_BIN (or using the Makefile, which at least requires cabal-install)
          #   Making agda-stdlib available (or disabling the relevant tests somehow)
          doCheck = false;
        });
      });
    };
  };
}
