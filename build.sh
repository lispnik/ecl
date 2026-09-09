#!/bin/sh
#
# Build ECL for iOS (arm64) straight out of this source tree.
#
#   ./build.sh
#
# Products:
#   ecl-native/   host ECL, built from this tree, used to drive the cross builds
#   ecl-iOS/      arm64 libraries and headers for the device
#   ecl-iOS-sim/  ditto for the arm64 simulator
#
# To force everything to be rebuilt from scratch:
#   rm -rf build build-native build-sim ecl-iOS ecl-iOS-sim ecl-native

set -e

SRC_DIR=`pwd`
MAKE_JOBS=9

XCODE_DIR=`xcode-select --print-path`
DEVICE_SDK="$XCODE_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
SIM_SDK="$XCODE_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"

# ---------------------------------------------------------------------------
# 1. Host ECL
#
# The cross build does not just *run* a host ECL, it reuses that ECL's dpp and
# ecl_min as its cross tools -- build/CROSS-DPP and build/CROSS-COMPILER are
# one-line scripts pointing straight at them. dpp resolves each @[pkg::sym] in
# the C sources to a numeric *index* into src/c/symbols_list.h, so a host ECL
# built from a different revision either dies on a symbol it has never heard of
# or, worse, silently resolves every symbol to the wrong index. The host ECL
# therefore has to come from this very tree, not from Homebrew or /usr/local.
# ---------------------------------------------------------------------------

NATIVE_PREFIX="$SRC_DIR/ecl-native"
NATIVE_BUILDDIR="$SRC_DIR/build-native"
NATIVE_ECL="$NATIVE_PREFIX/bin/ecl"

# Rebuild it if it is missing, or if the symbol table has moved on since.
if [ ! -x "$NATIVE_ECL" ] || [ "$SRC_DIR/src/c/symbols_list.h" -nt "$NATIVE_ECL" ]; then
  echo "=== building host ECL in $NATIVE_BUILDDIR ==="
  (
    # A host build, so none of the iOS settings below -- nor any inherited from
    # the caller's environment -- may leak into it. LIBRARY_PATH and friends
    # matter here: a Homebrew LIBRARY_PATH with no matching header path makes
    # configure find -lgmp but not gmp.h, and it then errors out rather than
    # falling back to the bundled copy.
    unset CC CXX CPP LD CFLAGS CXXFLAGS CPPFLAGS LDFLAGS LIBS ECL_TO_RUN
    unset LIBRARY_PATH CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH

    # `buildir' is honoured by the top-level configure; it keeps the host build
    # tree out of the cross build trees.
    # The bundled GMP is used on purpose: this ECL is a build tool, so it should
    # not depend on whatever happens to be installed on the machine.
    buildir="$NATIVE_BUILDDIR" ./configure --prefix="$NATIVE_PREFIX" \
                                           --disable-c99complex \
                                           --enable-gmp=included

    # Bypass the top-level Makefile: it hardcodes `cd build'.
    make -C "$NATIVE_BUILDDIR" -j${MAKE_JOBS}
    make -C "$NATIVE_BUILDDIR" install
  )
else
  echo "=== reusing host ECL in $NATIVE_PREFIX ==="
fi

# ---------------------------------------------------------------------------
# 2. Cross builds
#
# cross_build <build-dir> <prefix> <sdk> <platform-flags>
#
# The platform flags are what separate a device build from a simulator one:
# clang picks the Mach-O platform from the -m*-version-min flag paired with the
# matching -isysroot, and the two must agree or the objects will not link into
# an app for that destination.
# ---------------------------------------------------------------------------

cross_build() {
  cb_builddir=$1
  cb_prefix=$2
  cb_sdk=$3
  cb_platform=$4

  # Reconfiguring on top of a finished cross build tree leaves it inconsistent
  # -- ecl_min then dies part-way through building the target image -- so the
  # tree is thrown away and rebuilt every time. The expensive part, the host
  # ECL above, is what gets cached.
  rm -rf "$cb_builddir" "$cb_prefix"

  (
    CFLAGS="$cb_platform -isysroot $cb_sdk"
    CFLAGS="$CFLAGS -pipe -Wno-trigraphs -Wreturn-type -Wunused-variable"
    CFLAGS="$CFLAGS -fpascal-strings -fasm-blocks -fmessage-length=0 -fvisibility=hidden"
    CFLAGS="$CFLAGS -O2 -DNO_ASM"
    CFLAGS="$CFLAGS -DGC_DISABLE_INCREMENTAL -DECL_RWLOCK"

    export CC="clang"
    export CXX="clang++"
    export LD="ld"
    export CFLAGS
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="$cb_platform -isysroot $cb_sdk -pipe -std=c99 -gdwarf-2"
    export LIBS="-framework Foundation"
    export ECL_TO_RUN="$NATIVE_ECL"

    buildir="$cb_builddir" ./configure \
        --host=aarch64-apple-darwin \
        --prefix="$cb_prefix" \
        --disable-c99complex \
        --disable-shared \
        --with-cross-config="$SRC_DIR/src/util/iOS-arm64.cross_config"

    make -C "$cb_builddir" -j${MAKE_JOBS}
    make -C "$cb_builddir" install
  )
}

echo "=== cross-building ECL for the iOS device ==="
cross_build "$SRC_DIR/build" "$SRC_DIR/ecl-iOS" "$DEVICE_SDK" \
            "-arch arm64 -miphoneos-version-min=8.0"

echo "=== cross-building ECL for the iOS simulator ==="
cross_build "$SRC_DIR/build-sim" "$SRC_DIR/ecl-iOS-sim" "$SIM_SDK" \
            "-arch arm64 -mios-simulator-version-min=15.0"

echo
echo "=== done ==="
echo "  device:    $SRC_DIR/ecl-iOS"
echo "  simulator: $SRC_DIR/ecl-iOS-sim"
