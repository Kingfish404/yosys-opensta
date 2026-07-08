#!/usr/bin/env bash
################################################################################
# build_opensta.sh -- build OpenSTA (+ CUDD) natively on macOS / Linux.
################################################################################
# No Docker. Compiles CUDD 3.0.0 and OpenSTA under third_party/ and leaves the
# binary at third_party/OpenSTA/build/sta, which the Makefile auto-detects
# (OPENSTA_BIN).
#
# Dependencies (macOS / Homebrew):
#   brew install cmake swig bison flex eigen tcl-tk fmt
# On Linux install the equivalents (cmake, swig, bison, flex, libeigen3-dev,
# tcl-dev, libfmt-dev) and this script falls back to system locations.
################################################################################
set -euo pipefail

# Repo root = scripts/.. (the yosys-opensta checkout root)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TP="$ROOT/third_party"
mkdir -p "$TP"
cd "$TP"

NPROC="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"

OPENSTA_REPO="https://github.com/parallaxsw/OpenSTA.git"
CUDD_REPO="https://github.com/davidkebo/cudd.git"

# ---- Resolve Homebrew keg-only / package locations (macOS) ------------------
BREW="$(command -v brew || true)"
CMAKE_EXTRA=()
if [[ -n "$BREW" ]]; then
    echo "[build_opensta] Homebrew detected -> resolving keg-only tool paths"
    TCL_PREFIX="$($BREW --prefix tcl-tk 2>/dev/null || true)"
    BISON_PREFIX="$($BREW --prefix bison 2>/dev/null || true)"
    FLEX_PREFIX="$($BREW --prefix flex 2>/dev/null || true)"
    EIGEN_PREFIX="$($BREW --prefix eigen 2>/dev/null || true)"
    FMT_PREFIX="$($BREW --prefix fmt 2>/dev/null || true)"
    # tcl-tk on brew is Tcl 9; OpenSTA's FindTCL only auto-detects 8.x, so hint it.
    TCL_LIB="$(ls "$TCL_PREFIX"/lib/libtcl9*.dylib 2>/dev/null | head -1 || true)"
    [[ -z "$TCL_LIB" ]] && TCL_LIB="$(ls "$TCL_PREFIX"/lib/libtcl8*.dylib 2>/dev/null | head -1 || true)"
    TCL_HDR="$(ls "$TCL_PREFIX"/include/tcl-tk/tcl.h "$TCL_PREFIX"/include/tcl.h 2>/dev/null | head -1 || true)"
    [[ -n "$TCL_LIB" ]] && CMAKE_EXTRA+=("-DTCL_LIBRARY=$TCL_LIB")
    [[ -n "$TCL_HDR" ]] && CMAKE_EXTRA+=("-DTCL_HEADER=$TCL_HDR")
    [[ -x "$BISON_PREFIX/bin/bison" ]] && CMAKE_EXTRA+=("-DBISON_EXECUTABLE=$BISON_PREFIX/bin/bison")
    [[ -d "$FLEX_PREFIX" ]] && CMAKE_EXTRA+=("-DFLEX_EXECUTABLE=$FLEX_PREFIX/bin/flex" "-DFLEX_INCLUDE_DIR=$FLEX_PREFIX/include")
    PREFIX_PATH="$EIGEN_PREFIX;$FMT_PREFIX"
    CMAKE_EXTRA+=("-DCMAKE_PREFIX_PATH=$PREFIX_PATH")
    # Keg-only bison/flex are not symlinked into PATH; prepend them for the build.
    export PATH="$FLEX_PREFIX/bin:$BISON_PREFIX/bin:$PATH"
fi

# ---- CUDD (required by OpenSTA's power engine) ------------------------------
if [[ ! -f "$TP/cudd/lib/libcudd.a" ]]; then
    echo "[build_opensta] building CUDD 3.0.0"
    [[ -d cudd-src ]] || git clone --depth 1 "$CUDD_REPO" cudd-src
    rm -rf cudd-3.0.0
    tar xzf cudd-src/cudd_versions/cudd-3.0.0.tar.gz
    ( cd cudd-3.0.0 \
        && ./configure --prefix="$TP/cudd" --enable-shared >/dev/null \
        && make -j"$NPROC" >/dev/null \
        && make install >/dev/null )
else
    echo "[build_opensta] CUDD already built -> $TP/cudd"
fi

# ---- OpenSTA ----------------------------------------------------------------
echo "[build_opensta] cloning + building OpenSTA"
[[ -d OpenSTA ]] || git clone --depth 1 "$OPENSTA_REPO" OpenSTA
cd OpenSTA
cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_TCL_READLINE=OFF \
    -DCUDD_DIR="$TP/cudd" \
    -DCUDD_LIB="$TP/cudd/lib/libcudd.a" \
    -DCUDD_INCLUDE="$TP/cudd/include" \
    ${CMAKE_EXTRA[@]+"${CMAKE_EXTRA[@]}"}
cmake --build build -j"$NPROC"

echo "[build_opensta] done -> $TP/OpenSTA/build/sta"
"$TP/OpenSTA/build/sta" -version
