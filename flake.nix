{
  description = "Agda is a dependently typed programming language / interactive theorem prover.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
    ghc-debug = {
      url =
        "git+https://gitlab.haskell.org/wavewave/ghc-debug.git?ref=wavewave/ghc94";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, ghc-debug }: (flake-utils.lib.eachDefaultSystem (system: let
    pkgs = import nixpkgs {
      inherit system; overlays = [ self.overlay ];
      config.allowBroken = true;
    };
    hspkgs = pkgs.haskell.packages.ghc942.extend (hself: hsuper: {
      "ghc-debug-stub" = pkgs.haskell.lib.doJailbreak
        (hself.callCabal2nix "ghc-debug-stub" "${ghc-debug}/stub" { });
      "ghc-debug-convention" =
        hself.callCabal2nix "ghc-debug-convention" "${ghc-debug}/convention"
        { };
    });

  in {
    packages = {
      inherit (pkgs.haskellPackages) Agda;

      # TODO agda2-mode
    };

    defaultPackage = self.packages.${system}.Agda;

    devShell = let
      hsenv = hspkgs.ghcWithPackages (p: [
        p.aeson
        p.array
        p.async
        p.base
        p.binary
        p.blaze-html
        p.boxes
        p.bytestring
        p.case-insensitive
        p.containers
        p.data-hash
        p.deepseq
        p.directory
        p.dlist
        p.edit-distance
        p.equivalence
        p.exceptions
        p.filepath
        p.ghc-debug-stub
        p.gitrev
        p.hashable
        p.haskeline
        p.monad-control
        p.mtl
        p.murmur-hash
        p.parallel
        p.pretty
        p.process
        p.regex-tdfa
        p.split
        p.stm
        p.STMonadTrans
        p.strict
        p.text
        p.time
        p.time-compat
        p.transformers
        p.unordered-containers
        p.uri-encode
        p.vector
        p.vector-hashtables
        p.zlib
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
