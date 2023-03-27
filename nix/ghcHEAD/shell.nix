{
  system,
  pkgs
}: let
  bootGHC = "ghc925";
  hsenv = pkgs.haskell.packages.${bootGHC}.ghcWithPackages (p: [
    p.shake
    p.QuickCheck
  ]);
in
  # ghc.nix shell
  pkgs.mkShell {
    name = "ghcHEAD-shell";
    buildInputs = [
      hsenv
      pkgs.cabal-install
      pkgs.alex
      pkgs.happy
      pkgs.python3

      pkgs.autoconf
      pkgs.automake
      pkgs.m4
      pkgs.less
      pkgs.gmp.dev
      pkgs.gmp.out
      pkgs.glibcLocales
      pkgs.ncurses.dev
      pkgs.ncurses.out
      pkgs.zlib.dev
      pkgs.zlib.out

      # Agda dep
      pkgs.numactl
    ];
    CONFIGURE_ARGS = [
      "--with-gmp-includes=${pkgs.gmp.dev}/include"
      "--with-gmp-libraries=${pkgs.gmp}/lib"
      "--with-curses-includes=${pkgs.ncurses.dev}/include"
      "--with-curses-libraries=${pkgs.ncurses.out}/lib"
    ];
    shellHook = ''
      export CC=${pkgs.stdenv.cc}/bin/cc
      export GHC=${hsenv}/bin/ghc
      export GHCPKG=${hsenv}/bin/ghc-pkg
      export PS1="\n[ghcHEAD-agda:\w]$ \0"
    '';
  }
