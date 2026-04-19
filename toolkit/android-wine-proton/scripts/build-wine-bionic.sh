#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SOURCE_DIR="${WINE_SOURCE_DIR:-$(dirname "$SCRIPT_DIR")/wine-source}"
BUILD_DIR="${BUILD_DIR:-$(dirname "$SCRIPT_DIR")/wine-build}"
DEPS_PREFIX="${TERMUX_DEPS_PREFIX:-/data/data/com.termux/files/usr}"
NDK_PATH="${ANDROID_NDK_HOME:-}"
LLVM_MINGW_ROOT="${LLVM_MINGW_ROOT:-/opt/llvm-mingw}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
PROFILE_VERSION="${PROFILE_VERSION:-wine-bionic}"
PROFILE_VERSION_CODE="${PROFILE_VERSION_CODE:-1}"
WINE_DISPLAY_VERSION="${WINE_DISPLAY_VERSION:-}"
WINE_PROFILE_DESCRIPTION_PREFIX="${WINE_PROFILE_DESCRIPTION_PREFIX:-Wine Bionic ref4ik build}"
WINE_PREFIX_PACK_URL="${WINE_PREFIX_PACK_URL:-}"
APP_ID="${WINLATOR_APP_ID:-app.gamenative}"
ANDROID_API=28
TARGET_ARCH="x86_64"
WOW64_ARCHES="x86_64,i386"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-dir) SOURCE_DIR="$2"; shift 2 ;;
        --build-dir) BUILD_DIR="$2"; shift 2 ;;
        --deps-prefix) DEPS_PREFIX="$2"; shift 2 ;;
        --jobs) JOBS="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -n "$NDK_PATH" ]] || { echo "ANDROID_NDK_HOME is required" >&2; exit 1; }
[[ -d "$SOURCE_DIR" ]] || { echo "Missing source dir: $SOURCE_DIR" >&2; exit 1; }
[[ -d "$LLVM_MINGW_ROOT/bin" ]] || { echo "Missing llvm-mingw dir: $LLVM_MINGW_ROOT/bin" >&2; exit 1; }

TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin"
TARGET="${TARGET_ARCH}-linux-android"
REAL_CC="$TOOLCHAIN/${TARGET}${ANDROID_API}-clang"
REAL_CXX="$TOOLCHAIN/${TARGET}${ANDROID_API}-clang++"
AR="$TOOLCHAIN/llvm-ar"
RANLIB="$TOOLCHAIN/llvm-ranlib"
STRIP="$TOOLCHAIN/llvm-strip"
DLLTOOL="$LLVM_MINGW_ROOT/bin/llvm-dlltool"
export PATH="$LLVM_MINGW_ROOT/bin:$PATH"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/host" "$BUILD_DIR/target" "$BUILD_DIR/install" "$BUILD_DIR/toolchain-wrappers" output
LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/build-$(date -u +%Y%m%d-%H%M%S).log"

cat >"$BUILD_DIR/toolchain-wrappers/android-clang-filter.sh" <<EOF
#!/bin/bash
set -euo pipefail
real_compiler="\$1"
shift
filtered=()
for arg in "\$@"; do
    if [[ "\$arg" == "-mabi=ms" ]]; then
        continue
    fi
    filtered+=("\$arg")
done
exec "\$real_compiler" "\${filtered[@]}"
EOF
chmod +x "$BUILD_DIR/toolchain-wrappers/android-clang-filter.sh"

CC="$BUILD_DIR/toolchain-wrappers/cc"
CXX="$BUILD_DIR/toolchain-wrappers/cxx"
cat >"$CC" <<EOF
#!/bin/bash
exec "$BUILD_DIR/toolchain-wrappers/android-clang-filter.sh" "$REAL_CC" "\$@"
EOF
cat >"$CXX" <<EOF
#!/bin/bash
exec "$BUILD_DIR/toolchain-wrappers/android-clang-filter.sh" "$REAL_CXX" "\$@"
EOF
chmod +x "$CC" "$CXX"

log() {
    echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"
}

run_step() {
    local name="$1"
    shift
    local step_log="$LOG_DIR/${name}.log"
    log "Running step: $name"
    if "$@" >"$step_log" 2>&1; then
        log "Step finished: $name"
    else
        log "Step failed: $name"
        if grep -n -m 20 "error:" "$step_log" >/tmp/wine-step-errors.$$ 2>/dev/null; then
            log "First compiler/tool errors from $name:"
            cat /tmp/wine-step-errors.$$ | tee -a "$LOG_FILE"
        fi
        rm -f /tmp/wine-step-errors.$$
        tail -n 200 "$step_log" | tee -a "$LOG_FILE"
        exit 1
    fi
}

run_in_dir() {
    local name="$1"
    local dir="$2"
    shift 2
    run_step "$name" bash -lc "cd \"$dir\" && $*"
}

log "Full log: $LOG_FILE"
log "Using llvm-mingw from: $LLVM_MINGW_ROOT/bin"
run_in_dir prepare-build-system "$SOURCE_DIR" "./tools/make_requests && ./tools/make_specfiles && ./tools/make_makefiles && autoreconf -f"

run_step configure-host-tools env -u CC -u CXX -u CPPFLAGS -u CFLAGS -u CXXFLAGS -u LDFLAGS -u PKG_CONFIG_LIBDIR -u ACLOCAL_PATH \
    -u FREETYPE_CFLAGS -u PULSE_CFLAGS -u PULSE_LIBS -u SDL2_CFLAGS -u SDL2_LIBS -u X_CFLAGS -u X_LIBS \
    -u GSTREAMER_CFLAGS -u GSTREAMER_LIBS -u FFMPEG_CFLAGS -u FFMPEG_LIBS \
    bash -lc "cd \"$BUILD_DIR/host\" && \"$SOURCE_DIR/configure\" \
        --without-x \
        --without-gstreamer \
        --without-vulkan \
        --without-wayland \
        --enable-wineandroid_drv=no"

run_step build-host-tools env -u CC -u CXX -u CPPFLAGS -u CFLAGS -u CXXFLAGS -u LDFLAGS -u PKG_CONFIG_LIBDIR -u ACLOCAL_PATH \
    -u FREETYPE_CFLAGS -u PULSE_CFLAGS -u PULSE_LIBS -u SDL2_CFLAGS -u SDL2_LIBS -u X_CFLAGS -u X_LIBS \
    -u GSTREAMER_CFLAGS -u GSTREAMER_LIBS -u FFMPEG_CFLAGS -u FFMPEG_LIBS \
    make -C "$BUILD_DIR/host" -j"$JOBS" __tooldeps__

export PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig:$DEPS_PREFIX/share/pkgconfig"
export ACLOCAL_PATH="$DEPS_PREFIX/lib/aclocal:$DEPS_PREFIX/share/aclocal"
export CPPFLAGS="-I$DEPS_PREFIX/include/"
export CFLAGS="-march=x86-64 -mtune=generic"
export CXXFLAGS="-march=x86-64 -mtune=generic"
export LDFLAGS="-L$DEPS_PREFIX/lib -Wl,-rpath=$DEPS_PREFIX/lib"
export FREETYPE_CFLAGS="-I$DEPS_PREFIX/include/freetype2"
export PULSE_CFLAGS="-I$DEPS_PREFIX/include/pulse"
export PULSE_LIBS="-L$DEPS_PREFIX/lib/pulseaudio -lpulse"
export SDL2_CFLAGS="-I$DEPS_PREFIX/include/SDL2"
export SDL2_LIBS="-L$DEPS_PREFIX/lib -lSDL2"
export X_CFLAGS="-I$DEPS_PREFIX/include"
export X_LIBS="-L$DEPS_PREFIX/lib"
export GSTREAMER_CFLAGS="-I$DEPS_PREFIX/include/gstreamer-1.0 -I$DEPS_PREFIX/include/glib-2.0 -I$DEPS_PREFIX/lib/glib-2.0/include -I$DEPS_PREFIX/lib/gstreamer-1.0/include"
export GSTREAMER_LIBS="-L$DEPS_PREFIX/lib -lgstgl-1.0 -lgstapp-1.0 -lgstvideo-1.0 -lgstaudio-1.0 -lglib-2.0 -lgobject-2.0 -lgio-2.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0"
export FFMPEG_CFLAGS=""
export FFMPEG_LIBS=""

PREFIX="/data/data/${APP_ID}/files/imagefs/opt/${PROFILE_VERSION}-${TARGET_ARCH}"

run_step configure-target bash -lc "cd \"$BUILD_DIR/target\" && \"$SOURCE_DIR/configure\" \
        --host="$TARGET" \
        --with-wine-tools="$BUILD_DIR/host" \
        --with-mingw=\"$LLVM_MINGW_ROOT/bin/clang\" \
        --without-ldap \
        --without-oss \
        --disable-win16 \
        --disable-tests \
        --with-pulse \
        --without-ffmpeg \
        --with-gstreamer \
        --with-pthread \
        --without-dbus \
        --with-freetype \
        --enable-wineandroid_drv=no \
        --without-cups \
        --without-v4l2 \
        --enable-nls \
        --without-capi \
        --without-coreaudio \
        --without-gettext \
        --with-gettextpo=no \
        --without-gphoto \
        --without-inotify \
        --without-netapi \
        --without-opencl \
        --without-pcap \
        --without-sane \
        --without-udev \
        --without-unwind \
        --without-usb \
        --without-xfixes \
        --without-xcomposite \
        --with-xcursor \
        --without-xinerama \
        --without-xinput \
        --without-xinput2 \
        --without-xrandr \
        --without-xrender \
        --without-xshape \
        --without-xshm \
        --without-xxf86vm \
        --enable-archs="$WOW64_ARCHES" \
        --without-wayland \
        --without-pcsclite \
        --prefix="$PREFIX" \
        --bindir="$PREFIX/bin" \
        --libdir="$PREFIX/lib" \
        CC="$CC" \
        AS="$CC" \
        CXX="$CXX" \
        AR="$AR" \
        RANLIB="$RANLIB" \
        STRIP="$STRIP" \
        DLLTOOL=\"$DLLTOOL\""

run_step build-target-nls make -C "$BUILD_DIR/target" -j"$JOBS" nls/all
run_step build-and-install-target make -C "$BUILD_DIR/target" -j"$JOBS" install DESTDIR="$BUILD_DIR/install"

INNER="$BUILD_DIR/install/data/data/${APP_ID}/files/imagefs/opt/${PROFILE_VERSION}-${TARGET_ARCH}"
[[ -d "$INNER" ]] || { echo "Expected install dir missing: $INNER" >&2; exit 1; }
cp -r "$INNER/." "$BUILD_DIR/install/"
rm -rf "$BUILD_DIR/install/data"

DATE_TAG="$(git -C "$SOURCE_DIR" log -1 --format='%cd' --date=format:'%Y%m%d')"
GIT_HASH="$(git -C "$SOURCE_DIR" rev-parse --short HEAD)"
DISPLAY_VERSION="$WINE_DISPLAY_VERSION"
if [[ -z "$DISPLAY_VERSION" ]]; then
    DISPLAY_VERSION="$PROFILE_VERSION"
fi
if [[ "$DISPLAY_VERSION" == wine-* ]]; then
    PROFILE_VERSION_NAME="${DISPLAY_VERSION}-${TARGET_ARCH}"
else
    PROFILE_VERSION_NAME="wine-${DISPLAY_VERSION}-${TARGET_ARCH}"
fi
VERSION_NAME="${PROFILE_VERSION_NAME}-${DATE_TAG}-${GIT_HASH}"

run_step package-tar tar -Jcf "output/${VERSION_NAME}.tar.xz" -C "$BUILD_DIR/install" bin lib share
sha256sum "output/${VERSION_NAME}.tar.xz" > "output/${VERSION_NAME}.tar.xz.sha256"

PREFIX_PACK_SOURCE=""
for candidate in "$SCRIPT_DIR/reference/extracted/prefixPack.tzst" "$SCRIPT_DIR/reference/extracted/prefixPack.txz"; do
    if [[ -f "$candidate" ]]; then
        PREFIX_PACK_SOURCE="$candidate"
        break
    fi
done

if [[ -n "$PREFIX_PACK_SOURCE" ]]; then
    PREFIX_PACK_NAME="$(basename "$PREFIX_PACK_SOURCE")"
    cp "$PREFIX_PACK_SOURCE" "$BUILD_DIR/install/$PREFIX_PACK_NAME"
    python3 "$SCRIPT_DIR/generate_profile.py" \
        "$BUILD_DIR/install/profile.json" \
        "$PROFILE_VERSION_NAME" \
        "$PROFILE_VERSION_CODE" \
        "${WINE_PROFILE_DESCRIPTION_PREFIX} ${TARGET_ARCH} ${DATE_TAG} (${GIT_HASH})" \
        wine \
        "$PREFIX_PACK_NAME"
    run_step package-wcp bash "$SCRIPT_DIR/create-proton-wcp.sh" \
        "$BUILD_DIR/install" \
        "output/${VERSION_NAME}.wcp" \
        "$PROFILE_VERSION_NAME" \
        "$PROFILE_VERSION_CODE" \
        "${WINE_PROFILE_DESCRIPTION_PREFIX} ${TARGET_ARCH} ${DATE_TAG} (${GIT_HASH})" \
        wine
fi

log "Plain Wine ${TARGET_ARCH} artifacts written to output/"
