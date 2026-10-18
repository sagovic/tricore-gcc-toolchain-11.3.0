# TriCore (Infineon AURIX) bare-metal toolchain: GCC 11.3 (C/C++), binutils
# for tricore-elf and the GTM's mcs-elf, newlib and libatomic.
#
# Mirrors the build-toolchain script of EEESlab/tricore-gcc-toolchain-11.3.0
# stage by stage (binutils-mcs, binutils, gcc stage 1, newlib, gcc stage 2)
# with the same configure flags and static host programs, except:
# - binutils is really static here. upstream's -static never reaches its
#   programs: libtool drops it, so they link against the host's shared glibc.
#   libtool's own -all-static does get through.
# - plugins are off, since a static program can't load them: binutils
#   --disable-plugins (which also keeps gcc off its LTO linker plugin; -flto
#   works without it), gcc --disable-plugin and --disable-libcc1.
# - newlib's --host=i686-w64-mingw32 --build=i686-pc-mingw32, copied over from
#   the MSYS2 script. newlib only builds target code; host is just this box.
{
  lib,
  stdenv,
  fetchurl,
  bison,
  flex,
  gettext,
  m4,
  perl,
  texinfo,
  gccSrc,
  binutilsSrc,
  newlibSrc,
}:

let
  target = "tricore-elf";

  # built in-tree, at the versions contrib/download_prerequisites pins (sha512s
  # from contrib/prerequisites.sha512). nixpkgs' gmp/mpfr/libmpc are years
  # newer than anything GCC 11 was released against.
  prerequisites = [
    {
      name = "gmp";
      file = "gmp-6.1.0.tar.bz2";
      sha512 = "3c82aeab9c1596d4da8afac2eec38e429e84f3211e1a572cf8fd2b546493c44c039b922a1133eaaa48bd7f3e11dbe795a384e21ed95cbe3ecc58d7ac02246117";
    }
    {
      name = "mpfr";
      file = "mpfr-3.1.6.tar.bz2";
      sha512 = "0c310dd7956be527884f8059c195a5aca1042b089d0927ac6341e6310b1250a7059bc61aaaab4dfb76c6ab8b67e440878ca203f72674529bbcb46770ed9b6885";
    }
    {
      name = "mpc";
      file = "mpc-1.0.3.tar.gz";
      sha512 = "0028b76df130720c1fad7de937a0d041224806ce5ef76589f19c7b49d956071a683e2f20d154c192a231e69756b19e48208f2889b0c13950ceb7b3cfaf059a43";
    }
    {
      name = "isl";
      file = "isl-0.18.tar.bz2";
      sha512 = "85d0b40f4dbf14cb99d17aa07048cdcab2dc3eb527d2fbb1e84c41b2de5f351025370e57448b63b2b8a8cf8a0843a089c3263f9baee1542d5c2e1cb37ed39d94";
    }
  ];

  unpackPrerequisite =
    p:
    let
      src = fetchurl {
        url = "https://gcc.gnu.org/pub/gcc/infrastructure/${p.file}";
        inherit (p) sha512;
      };
    in
    ''
      tar -xf ${src} -C gcc
      mv gcc/${lib.removeSuffix ".tar.gz" (lib.removeSuffix ".tar.bz2" p.file)} gcc/${p.name}
    '';

  prefix = "--prefix=${placeholder "out"}";

  binutilsFlags = t: [
    "--target=${t}"
    "--program-prefix=${t}-"
    prefix
    "--disable-threads"
    "--enable-nls"
    "--disable-itcl"
    "--disable-tk"
    "--disable-tcl"
    "--disable-winsup"
    "--disable-gdbtk"
    "--disable-libgui"
    "--disable-rda"
    "--disable-sid"
    "--disable-sim"
    "--disable-gdb"
    "--disable-newlib"
    "--disable-libgloss"
    "--disable-test-suite"
    "--enable-checking=release"
    "--with-gnu-ld"
    "--with-gnu-as"
    "--disable-werror"
    "--disable-plugins"
    # every lexer has %option noyywrap, so nothing needs flex's libfl, and
    # nixpkgs ships no static one for ar and ranlib to link
    "ac_cv_lib_lex=none needed"
  ];

  gccFlags = [
    "--target=${target}"
    prefix
    "--enable-lib32"
    "--disable-lib64"
    "--enable-languages=c,c++"
    "--enable-libstdcxx-debug-flags=-gdwarf-3 -g -O0 -D_GLIBCXX_ASSERTIONS"
    "--enable-c99"
    "--enable-long-long"
    "--enable-checking"
    "--enable-nls"
    "--enable-static"
    "--enable-libatomic"
    "--disable-threads"
    "--disable-shared"
    "--with-headers=yes"
    "--with-newlib=yes"
    "--enable-mingw-wildcard"
    "--disable-libstdcxx-pch"
    "--enable-newlib-elix-level=3"
    "--enable-newlib-io-long-long"
    "--disable-newlib-supplied-syscalls"
    "--disable-libssp"
    "--disable-test-suite"
    # a static gcc can't load plugins: the plugin API and libcc1 (gdb's
    # `compile` plugin) would be dead weight
    "--disable-plugin"
    "--disable-libcc1"
  ];

  stage2TargetFlags = "-g -gdwarf-3 -O2 -ffast-math -ffunction-sections -mfast-div -fno-common -mno-eabi-bitfield-limit";
  newlibTargetFlags = "-g -gdwarf-3 -O2 -ffunction-sections -mfast-div -fno-common";

  targetTools = lib.concatMapStrings (tool: ''
    export ${lib.toUpper tool}_FOR_TARGET=$out/bin/${target}-${tool}
  '') [ "ar" "as" "ld" "nm" "objdump" "ranlib" "strip" "readelf" ];
in
stdenv.mkDerivation {
  pname = "tricore-gcc-toolchain";
  version = "11.3.1";

  nativeBuildInputs = [
    bison
    flex
    gettext
    m4
    perl
    texinfo
  ];

  # the host binaries are only ever run as compilers; GCC 11 era code predates
  # some of the checks (fortify 3 in particular), so build it the way upstream does.
  hardeningDisable = [ "all" ];

  # three sources all named "source" in the store, plus gcc wants its
  # prerequisites inside its own tree, so unpack by hand into writable copies.
  # cp -p keeps the store's uniform mtimes, so make never decides a generated
  # file (configure, *.info, parsers) is stale and tries to regenerate it.
  unpackPhase = ''
    runHook preUnpack
    cp -pr --reflink=auto ${gccSrc} gcc
    cp -pr --reflink=auto ${binutilsSrc} binutils
    cp -pr --reflink=auto ${newlibSrc} newlib
    chmod -R u+w gcc binutils newlib
    ${lib.concatMapStrings unpackPrerequisite prerequisites}
    patchShebangs --build gcc binutils newlib
    runHook postUnpack
  '';

  patches = [
    # mcs_info_to_howto_rela is void, but bfd calls it as bool and treats false
    # as "unsupported relocation", so reading mcs-elf relocs depended on
    # whatever was left in %al. GCC 13 only warns; GCC 14+ rejects it outright.
    ./patches/binutils-mcs-info-to-howto-bool.patch
  ];

  # stdenv would swap every config.sub for upstream GNU's, which knows
  # tricore but not the mcs machine that EEESlab's binutils patches in.
  dontUpdateAutotoolsGnuConfigScripts = true;

  dontConfigure = true;

  # every stage is configured against, and installed into, $out before the
  # next one starts (gcc needs the installed binutils, newlib needs gcc stage 1,
  # stage 2 needs newlib's headers), so build and install are one phase.
  # each build tree is dropped once installed: the sandbox builds in a tmpfs
  # /tmp here, and keeping them all would peak around 10G instead of ~7G.
  buildPhase = ''
    runHook preBuild

    top=$PWD
    export PATH=$out/bin:$PATH

    # -static needs glibc's libc.a. as a buildInput its directory would come
    # ahead of libc.so's and turn configure's ordinary dynamic test programs
    # into broken half-static ones; appended last, only -static finds it.
    export NIX_LDFLAGS="$NIX_LDFLAGS -L${stdenv.cc.libc}/lib -L${stdenv.cc.libc.static}/lib"

    # stage NAME SRC MAKE-ARGS INSTALL-TARGET CONFIGURE-ARGS...
    # MAKE-ARGS is split on spaces, so it can carry variable overrides.
    stage() {
      local name=$1 src=$2 build=$3 install=$4
      shift 4
      echo "=== $name"
      mkdir "$top/build-$name"
      pushd "$top/build-$name"
      "$top/$src/configure" "$@"
      # subdirectories otherwise configure on demand during the build; doing
      # it first keeps a make-time LDFLAGS out of their configure tests
      make -j"$NIX_BUILD_CORES" configure-host
      make -j"$NIX_BUILD_CORES" $build
      make "$install"
      popd
      rm -rf "$top/build-$name"
    }

    # -all-static is libtool's: plain gcc, as in configure tests, rejects it
    stage binutils-mcs binutils "all LDFLAGS=-all-static" install \
      LDFLAGS=-static ${lib.escapeShellArgs (binutilsFlags "mcs-elf")}

    stage binutils binutils "all LDFLAGS=-all-static" install \
      LDFLAGS=-static ${lib.escapeShellArgs (binutilsFlags target ++ [ "--enable-targets=mcs-elf" ])}

    stage gcc-stage1 gcc all-gcc install-gcc \
      LDFLAGS=-static ${lib.escapeShellArgs (gccFlags ++ [
        "CFLAGS_FOR_TARGET=-g -O2 -gdwarf-3"
        "CXXFLAGS_FOR_TARGET=-g -O2 -gdwarf-3"
      ])}

    (
      export CC_FOR_TARGET=$out/bin/${target}-gcc
      export CXX_FOR_TARGET=$out/bin/${target}-c++
      export GCC_FOR_TARGET=$out/bin/${target}-gcc
      ${targetTools}
      export CFLAGS_FOR_TARGET=${lib.escapeShellArg newlibTargetFlags}
      export CXXFLAGS_FOR_TARGET=${lib.escapeShellArg newlibTargetFlags}
      stage newlib newlib all install \
        --target=${target} ${lib.escapeShellArg prefix}
    )

    stage gcc-stage2 gcc all install \
      LDFLAGS=-static ${lib.escapeShellArgs (gccFlags ++ [
        "--with-gnu-ld"
        "--with-gnu-as"
        "CFLAGS_FOR_TARGET=${stage2TargetFlags}"
        "CXXFLAGS_FOR_TARGET=${stage2TargetFlags}"
      ])}

    runHook postBuild
  '';

  dontInstall = true;

  # only strip the x86 host programs. lib/gcc and tricore-elf/lib hold the
  # target libraries, which upstream deliberately builds with -g so they can
  # be stepped through in a debugger.
  stripDebugList = [
    "bin"
    "libexec"
    "${target}/bin"
    "mcs-elf/bin"
  ];

  # for windows.nix, which configures the same components for another host
  passthru = { inherit target binutilsFlags gccFlags; };

  meta = {
    description = "GCC 11.3 bare-metal toolchain for Infineon AURIX TriCore (tricore-elf, mcs-elf)";
    homepage = "https://github.com/EEESlab/tricore-gcc-toolchain-11.3.0";
    license = with lib.licenses; [
      gpl3Plus
      lgpl3Plus
      bsd3
    ];
    platforms = lib.platforms.linux;
    # binutils' bfd/opcodes translations, its ctf/sframe info pages and gcc's
    # man7 license pages share paths with any native gcc, binutils or gdb in
    # the same profile. the tricore programs read those from their own store
    # path, never the profile, so let the native package win the collision.
    # below lowPrio (10): the native gcc and binutils wrappers already sit at
    # 10, and equal priorities are a buildEnv error, not a tie-break.
    priority = 20;
  };
}
