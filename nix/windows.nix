# The same toolchain as Windows programs (x86_64-w64-mingw32), cross-compiled
# from Linux. Upstream builds natively in MSYS2 instead (build-toolchain-msys2,
# 32-bit MINGW32), and that script has drifted from the Linux one (no
# libatomic, plainer target flags); this follows the Linux one.
#
# Only the host programs are rebuilt: binutils for both targets and gcc's
# driver/cc1/cc1plus/lto1 (`all-gcc`). Everything that runs on the TriCore
# (newlib, libgcc, libstdc++, libatomic and their headers) doesn't depend on
# the host, so it's copied from the Linux package, whose tricore-elf-* tools
# also stand in for the target tools gcc's configure probes. Both toolchains
# thus link against byte-identical libraries, built once.
{
  lib,
  stdenv,
  buildPackages,
  bison,
  flex,
  m4,
  perl,
  removeReferencesTo,
  texinfo,
  tricore-gcc-toolchain,
}:

let
  linux = tricore-gcc-toolchain;
  inherit (linux) target binutilsFlags gccFlags;

  cross = [
    "--build=${stdenv.buildPlatform.config}"
    "--host=${stdenv.hostPlatform.config}"
  ];
in
stdenv.mkDerivation {
  pname = "tricore-gcc-toolchain-windows";
  patches = linux.patches ++ [
    # prefix.c and diagnostic-color.c include <windows.h> after system.h has
    # made abort() a macro, and current mingw-w64's OLE headers declare COM
    # methods named abort(). Lean-and-mean leaves OLE out but keeps the
    # registry and console APIs these two use; it's what pretty-print.c,
    # plugin.c and host-mingw32.c already do.
    ./patches/gcc-mingw-windows-h-lean-and-mean.patch
  ];

  inherit (linux)
    version
    unpackPhase
    dontUpdateAutotoolsGnuConfigScripts
    stripDebugList
    ;

  # gcc runs its generator programs (gen*) during the build, so it needs a
  # compiler for this machine too. gcc13 for the same reason as the Linux build.
  depsBuildBuild = [ buildPackages.gcc13Stdenv.cc ];
  nativeBuildInputs = [
    bison
    flex
    m4
    perl
    removeReferencesTo
    texinfo
    linux
  ];

  hardeningDisable = [ "all" ];

  # nixpkgs' MinGW compiler is GCC 16 (gcc13 for MinGW isn't in the binary
  # cache). It defaults to C23 and C++20; GCC 11 and the in-tree gmp/mpfr/mpc
  # were written against C17 and C++17, GCC 11's own default. -fpermissive
  # turns GCC 14's new C errors (implicit declarations, pointer mismatches)
  # back into the warnings the Linux build's GCC 13 gives for the same code.
  env.CFLAGS = "-O2 -std=gnu17 -fpermissive";

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    # on CXX, not CXXFLAGS: libcody insists on __cplusplus == 201103 and gets
    # there by appending -std=c++11 to CXX, which a CXXFLAGS -std would override.
    export CXX="$CXX -std=gnu++17"

    top=$PWD

    # stage NAME SRC MAKE-TARGET INSTALL-TARGET CONFIGURE-ARGS...
    stage() {
      local name=$1 src=$2 build=$3 install=$4
      shift 4
      echo "=== $name"
      mkdir "$top/build-$name"
      pushd "$top/build-$name"
      "$top/$src/configure" "$@"
      make -j"$NIX_BUILD_CORES" "$build"
      make "$install"
      popd
      rm -rf "$top/build-$name"
    }

    stage binutils-mcs binutils all install \
      ${lib.escapeShellArgs (cross ++ binutilsFlags "mcs-elf")}

    stage binutils binutils all install \
      ${lib.escapeShellArgs (cross ++ binutilsFlags target ++ [ "--enable-targets=mcs-elf" ])}

    # in place before gcc's configure, which has to find newlib's headers the
    # way the Linux stage 2 did (limits.h chaining, fixincludes).
    mkdir -p $out/lib $out/${target}
    cp -r --no-preserve=mode ${linux}/lib/gcc $out/lib/
    cp -r --no-preserve=mode ${linux}/${target}/include ${linux}/${target}/lib $out/${target}/
    mkdir -p $out/share
    cp -r --no-preserve=mode ${linux}/share/gcc-${linux.version} $out/share/

    # -static as upstream does: gcc's programs (cc1.exe in libexec\ too) would
    # otherwise import libmcfgthread-2.dll, which Windows only finds next to
    # the .exe or on PATH. binutils is plain C and imports no such DLL.
    stage gcc gcc all-gcc install-gcc \
      ${lib.escapeShellArgs (cross ++ gccFlags ++ [ "--with-gnu-ld" "--with-gnu-as" "LDFLAGS=-static" ])}

    # libtool archives and libstdc++'s gdb hook carry the Linux prefix; the
    # former are useless off Linux, the latter should point at this tree. What
    # remains is header paths in the target libraries' debug info, which would
    # otherwise make this package depend on the whole Linux toolchain.
    find $out -name '*.la' -delete
    grep -rlZ --binary-files=without-match ${linux} $out | xargs -0r sed -i "s|${linux}|$out|g"
    find $out -type f -exec remove-references-to -t ${linux} {} +

    runHook postBuild
  '';

  dontInstall = true;

  # the only scripts are gcc's install-tools; a Nix bash shebang means nothing
  # on Windows and would drag bash into the closure.
  dontPatchShebangs = true;

  meta = {
    description = "GCC 11.3 bare-metal toolchain for Infineon AURIX TriCore, as Windows (x86_64) programs";
    inherit (linux.meta) homepage license;
    platforms = lib.platforms.windows;
  };
}
