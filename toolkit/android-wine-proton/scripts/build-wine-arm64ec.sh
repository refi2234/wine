#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_START_TIME="$(date -u +%s)"

NDK_PATH="${ANDROID_NDK_HOME:-}"
SOURCE_DIR="${WINE_SOURCE_DIR:-$(dirname "$SCRIPT_DIR")/wine-source}"
BUILD_DIR="${BUILD_DIR:-$(dirname "$SCRIPT_DIR")/wine-build-arm64ec}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
CLEAN_BUILD=0
ANDROID_API=28

PROFILE_VERSION="${PROFILE_VERSION:-wine-arm64ec}"
PROFILE_VERSION_CODE="${PROFILE_VERSION_CODE:-1}"
WINE_DISPLAY_VERSION="${WINE_DISPLAY_VERSION:-11.0}"
PROFILE_ARCH_SUFFIX="${PROFILE_ARCH_SUFFIX:-arm64ec}"
WINE_PROFILE_DESCRIPTION_PREFIX="${WINE_PROFILE_DESCRIPTION_PREFIX:-Wine ARM64EC build}"
WINLATOR_APP_ID="${WINLATOR_APP_ID:-app.gamenative}"
DEPS_PREFIX="${TERMUX_DEPS_PREFIX:-/data/data/${WINLATOR_APP_ID}/files/imagefs/usr}"
WINE_PREFIX_PACK_URL="${WINE_PREFIX_PACK_URL:-https://github.com/nnnnnnnnnn3773/wineu11/releases/download/2236636/prefixPack.txz}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ndk-path) NDK_PATH="$2"; shift 2 ;;
        --source-dir) SOURCE_DIR="$2"; shift 2 ;;
        --build-dir) BUILD_DIR="$2"; shift 2 ;;
        --jobs) JOBS="$2"; shift 2 ;;
        --clean) CLEAN_BUILD=1; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/build-$(date -u +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
die() { log "ERROR: $*"; exit 1; }

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
            cat /tmp/wine-step-errors.$$
        fi
        rm -f /tmp/wine-step-errors.$$
        tail -n 200 "$step_log"
        exit 1
    fi
}

log "=== Plain Wine ARM64EC Android Build ==="
log "Build started: $(date -u)"
log "Jobs: $JOBS"
log "Log: $LOG_FILE"

if [[ -z "$NDK_PATH" ]]; then
    die "ANDROID_NDK_HOME not set. Use --ndk-path or export ANDROID_NDK_HOME."
fi
[[ -d "$NDK_PATH" ]] || die "NDK directory not found: $NDK_PATH"
[[ -d "$SOURCE_DIR" ]] || die "Wine source not found: $SOURCE_DIR"

if [[ ! -d "$DEPS_PREFIX" && -z "${TERMUX_DEPS_PREFIX:-}" ]]; then
    for candidate in \
        "/data/data/app.gamenative/files/imagefs/usr" \
        "/data/data/com.winlator.cmod/files/imagefs/usr" \
        "/data/data/com.winlator.ref4ik/files/imagefs/usr" \
        "/data/data/com.termux/files/usr" \
        "/data/data/com.winlator.cmod/files/usr"; do
        if [[ -d "$candidate" ]]; then
            log "Termux dependency prefix not found at $DEPS_PREFIX, using $candidate"
            DEPS_PREFIX="$candidate"
            break
        fi
    done
fi

log "Termux deps prefix: $DEPS_PREFIX"
[[ -d "$DEPS_PREFIX" ]] || die "Termux dependency prefix not found: $DEPS_PREFIX"

TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin"
TARGET="aarch64-linux-android${ANDROID_API}"
CC="${TOOLCHAIN}/${TARGET}-clang"
CXX="${TOOLCHAIN}/${TARGET}-clang++"
AR="${TOOLCHAIN}/llvm-ar"
STRIP="${TOOLCHAIN}/llvm-strip"

[[ -f "$CC" ]] || die "Compiler not found: $CC"

if [[ ! -f "$SOURCE_DIR/configure" && -f "$SOURCE_DIR/autogen.sh" ]]; then
    run_step autogen-source bash -lc "cd \"$SOURCE_DIR\" && bash autogen.sh"
fi
[[ -f "$SOURCE_DIR/configure" ]] || die "configure not found in $SOURCE_DIR"

if [[ $CLEAN_BUILD -eq 1 ]]; then
    log "Cleaning build directory: $BUILD_DIR"
    rm -rf "$BUILD_DIR/host" "$BUILD_DIR/target" "$BUILD_DIR/install"
fi

mkdir -p "$BUILD_DIR/host" "$BUILD_DIR/target" "$BUILD_DIR/install" output

GIT_HASH="unknown"
GIT_DATE="$(date -u +%Y%m%d)"
if git -C "$SOURCE_DIR" rev-parse HEAD &>/dev/null; then
    GIT_HASH="$(git -C "$SOURCE_DIR" rev-parse --short HEAD)"
    GIT_DATE="$(git -C "$SOURCE_DIR" log -1 --format='%cd' --date=format:'%Y%m%d')"
fi

PROFILE_VERSION_NAME="${WINE_DISPLAY_VERSION}-${PROFILE_ARCH_SUFFIX}"
DISPLAY_NAME="${WINE_PROFILE_DESCRIPTION_PREFIX} ${PROFILE_ARCH_SUFFIX} ${GIT_DATE} (${GIT_HASH})"
ARTIFACT_BASENAME="wine-${PROFILE_VERSION_NAME}-${GIT_DATE}-${GIT_HASH}"

log "Profile version name: $PROFILE_VERSION_NAME"
log "Artifact basename: $ARTIFACT_BASENAME"

run_step configure-host-tools bash -lc "cd \"$BUILD_DIR/host\" && env -u CC -u CXX \"$SOURCE_DIR/configure\" \
    --enable-win64 \
    --without-x \
    --without-freetype \
    --without-gnutls \
    --without-unwind \
    --without-pulse \
    --without-gstreamer \
    --without-alsa \
    --without-sdl \
    --without-vulkan \
    --without-cups \
    --without-krb5 \
    --without-netapi \
    --without-gphoto \
    --without-udev \
    --without-capi \
    --without-gettext \
    --with-gettextpo=no \
    --without-ffmpeg"

run_step build-host-tools make -C "$BUILD_DIR/host" -j"$JOBS" __tooldeps__

PREFIX="/data/data/${WINLATOR_APP_ID}/files/imagefs/opt/${PROFILE_VERSION}"
run_step configure-target bash -lc "cd \"$BUILD_DIR/target\" && \
    PKG_CONFIG_LIBDIR=\"$DEPS_PREFIX/lib/pkgconfig:$DEPS_PREFIX/share/pkgconfig\" \
    ACLOCAL_PATH=\"$DEPS_PREFIX/lib/aclocal:$DEPS_PREFIX/share/aclocal\" \
    CPPFLAGS=\"-I$DEPS_PREFIX/include\" \
    X_CFLAGS=\"-I$DEPS_PREFIX/include\" \
    X_LIBS=\"-L$DEPS_PREFIX/lib -landroid-sysvshm\" \
    \"$SOURCE_DIR/configure\" \
    --host=aarch64-linux-android \
    --with-wine-tools=\"$BUILD_DIR/host\" \
    --prefix=\"$PREFIX\" \
    --bindir=\"$PREFIX/bin\" \
    --libdir=\"$PREFIX/lib\" \
    --enable-archs=aarch64,i386 \
    --with-x \
    --x-includes=\"$DEPS_PREFIX/include\" \
    --x-libraries=\"$DEPS_PREFIX/lib\" \
    --without-xfixes \
    --without-xcomposite \
    --without-xcursor \
    --without-xinerama \
    --without-xinput \
    --without-xinput2 \
    --without-xrandr \
    --without-xrender \
    --without-xshape \
    --with-xshm \
    --without-xxf86vm \
    --enable-wineandroid_drv=no \
    --without-freetype \
    --without-gnutls \
    --without-unwind \
    --without-dbus \
    --without-sane \
    --without-netapi \
    --without-pulse \
    --without-gstreamer \
    --without-alsa \
    --without-sdl \
    --without-vulkan \
    --without-cups \
    --without-krb5 \
    --without-gphoto \
    --without-udev \
    --without-capi \
    --without-gettext \
    --with-gettextpo=no \
    --without-ffmpeg \
    CC=\"$CC\" \
    CXX=\"$CXX\" \
    AR=\"$AR\" \
    STRIP=\"$STRIP\" \
    TARGETCC=\"$CC\" \
    TARGETCXX=\"$CXX\" \
    CFLAGS=\"-O2 -DANDROID -fPIC -I$DEPS_PREFIX/include\" \
    LDFLAGS=\"-Wl,--build-id=sha1\""

run_step build-target-nls make -C "$BUILD_DIR/target" -j"$JOBS" nls/all
run_step build-and-install-target make -C "$BUILD_DIR/target" -j"$JOBS" install DESTDIR="$BUILD_DIR/install"

INNER="$BUILD_DIR/install/data/data/${WINLATOR_APP_ID}/files/imagefs/opt/${PROFILE_VERSION}"
[[ -d "$INNER" ]] || die "Expected install dir missing: $INNER"
cp -r "$INNER/." "$BUILD_DIR/install/"
rm -rf "$BUILD_DIR/install/data"

if ! find "$BUILD_DIR/install/lib/wine" -type f -name 'winex11.drv*' | grep -q .; then
    die "winex11.drv missing from staged Wine runtime; Winlator needs the X11 graphics driver"
fi

if ! find "$BUILD_DIR/install/lib/wine" -type f -path '*/aarch64-windows/ntdll.dll' | grep -q .; then
    die "aarch64-windows/ntdll.dll missing from staged Wine runtime"
fi

run_step package-tar tar -Jcf "output/${ARTIFACT_BASENAME}.tar.xz" -C "$BUILD_DIR/install" bin lib share
sha256sum "output/${ARTIFACT_BASENAME}.tar.xz" > "output/${ARTIFACT_BASENAME}.tar.xz.sha256"

PREFIX_PACK_NAME=""
if [[ -n "$WINE_PREFIX_PACK_URL" ]]; then
    mkdir -p "$SCRIPT_DIR/reference/extracted"
    PREFIX_PACK_NAME="$(basename "$WINE_PREFIX_PACK_URL")"
    if [[ ! -f "$SCRIPT_DIR/reference/extracted/$PREFIX_PACK_NAME" ]]; then
        run_step fetch-prefix-pack wget -q "$WINE_PREFIX_PACK_URL" -O "$SCRIPT_DIR/reference/extracted/$PREFIX_PACK_NAME"
    fi
fi

if [[ -n "$PREFIX_PACK_NAME" && -f "$SCRIPT_DIR/reference/extracted/$PREFIX_PACK_NAME" ]]; then
    cp "$SCRIPT_DIR/reference/extracted/$PREFIX_PACK_NAME" "$BUILD_DIR/install/$PREFIX_PACK_NAME"
fi

python3 "$SCRIPT_DIR/generate_profile.py" \
    "$BUILD_DIR/install/profile.json" \
    "$PROFILE_VERSION_NAME" \
    "$PROFILE_VERSION_CODE" \
    "$DISPLAY_NAME" \
    wine \
    "${PREFIX_PACK_NAME:-}"

run_step package-wcp bash "$SCRIPT_DIR/create-proton-wcp.sh" \
    "$BUILD_DIR/install" \
    "output/${ARTIFACT_BASENAME}.wcp" \
    "$PROFILE_VERSION_NAME" \
    "$PROFILE_VERSION_CODE" \
    "$DISPLAY_NAME" \
    wine

TOTAL_TIME=$(( $(date -u +%s) - BUILD_START_TIME ))
log "Plain Wine ARM64EC artifacts written to output/"
log "Total time: ${TOTAL_TIME}s ($(( TOTAL_TIME / 60 ))m)"
