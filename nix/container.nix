# OCI image of the Linux toolchain, for CI jobs and machines without Nix.
# Besides the toolchain, only what a firmware Makefile usually expects; anything
# more belongs in a derived image.
{
  buildEnv,
  dockerTools,
  bashInteractive,
  coreutils,
  diffutils,
  findutils,
  gawk,
  gnugrep,
  gnumake,
  gnused,
  gnutar,
  gzip,
  tricore-gcc-toolchain,
}:

dockerTools.buildLayeredImage {
  name = "ghcr.io/sagovic/tricore-gcc-toolchain";
  tag = tricore-gcc-toolchain.version;

  contents = [
    # bin/ only: the toolchain reaches its libexec and libraries through its
    # own store path, and linking share/ would collide on info and locale files.
    (buildEnv {
      name = "tricore-image-root";
      paths = [
        tricore-gcc-toolchain
        bashInteractive
        coreutils
        diffutils
        findutils
        gawk
        gnugrep
        gnumake
        gnused
        gnutar
        gzip
      ];
      pathsToLink = [ "/bin" ];
    })
    dockerTools.usrBinEnv
  ];

  # gcc writes its intermediate files to $TMPDIR, /tmp by default
  extraCommands = "mkdir -m 1777 tmp";

  config = {
    Cmd = [ "bash" ];
    WorkingDir = "/work";
    Env = [ "PATH=/bin" ];
    Labels = {
      # links the GHCR package to the repo
      "org.opencontainers.image.source" = "https://github.com/sagovic/tricore-gcc-toolchain-11.3.0";
      "org.opencontainers.image.description" = tricore-gcc-toolchain.meta.description;
      "org.opencontainers.image.licenses" = "GPL-3.0-or-later";
    };
  };
}
