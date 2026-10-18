{
  description = "GCC 11.3 bare-metal toolchain for Infineon AURIX TriCore (tricore-elf, mcs-elf)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # the submodule commits of EEESlab/tricore-gcc-toolchain-11.3.0 at dfa1efd,
    # pinned by commit: the umbrella repo is what tests them together, and
    # tricore-gcc's main is already past the commit it pins.
    # Bump: set all three revs to the umbrella's new `git submodule status`.
    tricore-gcc = {
      url = "github:EEESlab/tricore-gcc/df3095ae5b71df917e4fe2ff3be39620bbd4d213";
      flake = false;
    };
    tricore-binutils-gdb = {
      url = "github:EEESlab/tricore-binutils-gdb/c068019c17eeeefdbec9210cb46baefe2f78c383";
      flake = false;
    };
    tricore-newlib-cygwin = {
      url = "github:EEESlab/tricore-newlib-cygwin/240a8f676ea923c703824e996fbe88ac4a302e17";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      tricore-gcc,
      tricore-binutils-gdb,
      tricore-newlib-cygwin,
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          tricore-gcc-toolchain = pkgs.callPackage ./nix/package.nix {
            # GCC 15+ defaults to C23, which neither GCC 11's own C code nor
            # the in-tree gmp 6.1 configure checks survive. 13 still builds it.
            stdenv = pkgs.gcc13Stdenv;
            gccSrc = tricore-gcc;
            binutilsSrc = tricore-binutils-gdb;
            newlibSrc = tricore-newlib-cygwin;
          };
          default = tricore-gcc-toolchain;

          tricore-gcc-toolchain-windows = pkgs.pkgsCross.mingwW64.callPackage ./nix/windows.nix {
            inherit tricore-gcc-toolchain;
          };

          # what to hand a Windows user: unzip anywhere, put its bin\ on PATH.
          tricore-gcc-toolchain-windows-zip =
            let
              windows = tricore-gcc-toolchain-windows;
              dir = "tricore-gcc-toolchain-${windows.version}";
            in
            pkgs.runCommand "${dir}-${pkgs.pkgsCross.mingwW64.stdenv.hostPlatform.config}.zip"
              { nativeBuildInputs = [ pkgs.zip ]; }
              ''
                cp -r --no-preserve=mode ${windows} ${dir}
                zip -qr9 $out ${dir}
              '';

          container = pkgs.callPackage ./nix/container.nix { inherit tricore-gcc-toolchain; };
        }
      );

      # hands out this flake's own build rather than re-calling package.nix
      # with the consumer's nixpkgs: the toolchain is a ~25 min source build
      # that no binary cache has, so it should only rebuild when this flake's
      # lock moves, not on every bump of the consumer's nixpkgs.
      overlays.default = final: prev: {
        tricore-gcc-toolchain = self.packages.${prev.stdenv.hostPlatform.system}.default;
      };
    };
}
