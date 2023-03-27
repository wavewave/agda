{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/master";

  inputs.flake-utils.url = "github:numtide/flake-utils/v1.0.0";

  outputs = {
    self,
    flake-utils,
    nixpkgs,
    ...
  } @ inputs': let
    supportedSystems = ["x86_64-linux" "x86_64-darwin" "aarch64-darwin"];
  in
    flake-utils.lib.eachSystem supportedSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      devShells.default = import ./shell.nix {inherit system pkgs;};
    });
}
