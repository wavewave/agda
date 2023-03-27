{
  description = "Agda is a dependently typed programming language / interactive theorem prover.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
    ghc-debug = {
      url =
        "git+https://gitlab.haskell.org/ghc/ghc-debug.git?ref=master";
      flake = false;
    };
    hackage-index = {
      type = "file";
      flake = false;
      url =
        "https://api.github.com/repos/commercialhaskell/all-cabal-hashes/tarball/13a91ab76cfac2098eff2780f3d3b6224352a7a2";
    };
    ghc_nix = {
      url = "github:wavewave/ghc.nix/fix-hash-again";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-unstable.follows = "nixpkgs";
      inputs.all-cabal-hashes.follows = "hackage-index";
    };
  };

  outputs = { self, nixpkgs, flake-utils, ghc-debug, ... }@inputs: (flake-utils.lib.eachDefaultSystem (system: let
    pkgs = import nixpkgs {
      inherit system; overlays = [ self.overlay ];
      config.allowBroken = true;
    };
    hpkgsFor = compiler: pkgs.haskell.packages.${compiler}.extend (hself: hsuper: {
      "ghc-debug-stub" = pkgs.haskell.lib.doJailbreak
        (hself.callCabal2nix "ghc-debug-stub" "${ghc-debug}/stub" { });
      "ghc-debug-convention" =
        hself.callCabal2nix "ghc-debug-convention" "${ghc-debug}/convention"
        { };
    });
    mkShellFor = compiler:
      let
        hsenv = (hpkgsFor compiler).ghcWithPackages (p: [
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

          p.eventlog2html
        ]);
      in pkgs.mkShell {
        inputsFrom = [ self.defaultPackage.${system} ];
        packages = with pkgs; [
          pkg-config
          zlib
          icu
          #haskellPackages.fix-whitespace
          hsenv
        ];
        shellHook = ''
          export PS1="\n[agda:\w]$ \0"
        '';
      };
    supportedCompilers = [ "ghc924" "ghc942" ];

    shellGHCHEAD = {
      "ghcHEAD" = (import ./nix/ghcHEAD/shell.nix {
        inherit (inputs) ghc_nix;
        inherit system pkgs ;
      }).ghcNixShell;
    };

  in {
    packages = {
      inherit (pkgs.haskellPackages) Agda;

      # TODO agda2-mode
    };

    defaultPackage = self.packages.${system}.Agda;

    devShells = pkgs.lib.genAttrs supportedCompilers mkShellFor // shellGHCHEAD;

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
