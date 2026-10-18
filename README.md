# TriCore GCC 11.3 toolchain (Nix)

A Nix flake for [EEESlab/tricore-gcc-toolchain-11.3.0](https://github.com/EEESlab/tricore-gcc-toolchain-11.3.0): GCC 11.3 (C/C++), binutils for `tricore-elf` and `mcs-elf`, newlib and libatomic, built from EEESlab's sources at the commits that repo pins.

## Build

```
nix build github:sagovic/tricore-gcc-toolchain-11.3.0
./result/bin/tricore-elf-gcc --version
```

Windows (x86_64) zip, cross-compiled from Linux:

```
nix build github:sagovic/tricore-gcc-toolchain-11.3.0#tricore-gcc-toolchain-windows-zip
```

## Container

The Linux toolchain with bash, coreutils and make, for machines without Nix:

```
podman run --rm -v "$PWD:/work" ghcr.io/sagovic/tricore-gcc-toolchain tricore-elf-gcc --version
```

## Use in a flake

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.tricore-toolchain.url = "github:sagovic/tricore-gcc-toolchain-11.3.0";

  outputs = { nixpkgs, tricore-toolchain, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [ tricore-toolchain.packages.${system}.default ];
      };
    };
}
```

Don't make its `nixpkgs` follow yours, or every update of yours rebuilds it.
