#!/usr/bin/env bash
#
# build.sh — build a minimal static ffmpeg (~3-4 MB) that contains only what
# OpenCall (github.com/Lamprozx/OpenCall) needs, instead of the ~347 MB ffmpeg
# that Termux ships by default.
#
# Included components
#   decode : mp3, wav (pcm_s16le), opus, h264, aac
#   encode : pcm_s16le (wav) + libx264 (baseline, 8-bit yuv420p)
#   filters: atempo, aecho, bass, treble, lowpass, highpass, chorus,
#            flanger, tremolo, vibrato, acrusher, afade, areverse,
#            asetrate, aresample, aformat, format, fps
#   demux  : mp3, wav, ogg, mov, matroska, h264, aac
#   mux    : wav, h264
#   bsf    : h264_metadata
#
# Usage:
#   ./build.sh arm64          # android/arm64 (Termux) -> out/ffmpeg-min-arm64
#   ./build.sh amd64          # native linux/amd64     -> out/ffmpeg-min-linux-amd64
#   ./build.sh --help         # show this help
#
# Requirements on the build machine: bash, curl, unzip, xz, make, git, a C
# toolchain. For android targets the Android NDK is downloaded automatically.
set -euo pipefail

NDK_VER="r26d"
NDK_API="24"
FFMPEG_VER="7.1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$ROOT/build"
OUT="$ROOT/out"

usage() {
  cat <<'EOF'
usage: ./build.sh <architecture>

architecture:
  arm64    build for android/arm64 (Termux), 64-bit
  amd64    build for native linux/amd64, 64-bit

examples:
  ./build.sh arm64
  ./build.sh amd64

look at 'README.md' for more information.
EOF
}

# 0) argument handling
case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  arm64|amd64)
    TARGET="$1"
    ;;
  "")
    echo "please insert a valid architecture, look at 'README.md' or use --help." >&2
    exit 1
    ;;
  *)
    echo "unknown architecture '$1'." >&2
    echo "please insert a valid architecture, look at 'README.md' or use --help." >&2
    exit 1
    ;;
esac

# disk space confirmation (BEFORE any download / tool check)
echo "This build downloads sources (NDK, ffmpeg, x264) and needs ~700 MB of disk."
read -r -p "Continue? [y/N] " ans
case "${ans:-}" in
  y|Y|yes|YES) ;;
  *)
    echo "aborted."
    exit 1
    ;;
esac

mkdir -p "$WORK" "$OUT"

# host toolchain sanity
for t in curl unzip xz make git; do
  command -v "$t" >/dev/null 2>&1 || { echo "missing tool: $t" >&2; exit 1; }
done

# x264 (static, 8-bit, yuv420p only)
X264_SRC="$WORK/x264"
if [ ! -d "$X264_SRC/.git" ]; then
  echo ">> cloning x264"
  git clone --depth 1 https://code.videolan.org/videolan/x264.git "$X264_SRC"
fi

build_x264() {
  local prefix="$1"; shift
  local cfg=("$@")
  ( cd "$X264_SRC" && make distclean >/dev/null 2>&1 || true
    ./configure --prefix="$prefix" --enable-static --disable-cli \
      --bit-depth=8 --chroma-format=420 "${cfg[@]}" >/dev/null
    make -j"$(nproc)" >/dev/null
    make install >/dev/null )
}

# ffmpeg source
FFMPEG_SRC="$WORK/ffmpeg-$FFMPEG_VER"
if [ ! -d "$FFMPEG_SRC" ]; then
  echo ">> downloading ffmpeg $FFMPEG_VER"
  curl -L -o "$WORK/ffmpeg.tar.xz" "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.xz"
  tar -C "$WORK" -xf "$WORK/ffmpeg.tar.xz"
fi

FFMPEG_CFG_COMMON=(
  --enable-static --disable-shared
  --disable-doc --disable-debug
  --disable-ffplay --disable-ffprobe
  --enable-gpl --enable-libx264
  --enable-avcodec --enable-avformat --enable-avfilter
  --enable-swresample --enable-swscale
  --enable-encoder=libx264,pcm_s16le
  --enable-decoder=mp3,mp3float,pcm_s16le,opus,h264,aac
  --enable-demuxer=mp3,wav,ogg,mov,matroska,h264,aac
  --enable-muxer=wav,h264
  --enable-protocol=file
  --enable-bsf=h264_metadata
  --enable-filter=atempo,aecho,bass,treble,lowpass,highpass,chorus,flanger,tremolo,vibrato,acrusher,afade,areverse,asetrate,aresample,aformat,format,fps
  --disable-everything
)

build_ffmpeg() {
  local prefix="$1"; shift
  ( cd "$FFMPEG_SRC" && make distclean >/dev/null 2>&1 || true
    ./configure --prefix="$prefix" "${FFMPEG_CFG_COMMON[@]}" "$@" >/dev/null
    make -j"$(nproc)" >/dev/null )
}

# build per target
case "$TARGET" in
  arm64)
    echo ">> target: android/arm64"
    NDK_DIR="$WORK/android-ndk-$NDK_VER"
    if [ ! -d "$NDK_DIR" ]; then
      echo ">> downloading Android NDK $NDK_VER"
      curl -L -o "$WORK/ndk.zip" "https://dl.google.com/android/repository/android-ndk-$NDK_VER-linux.zip"
      unzip -q "$WORK/ndk.zip" -d "$WORK"
    fi
    TC="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64"
    PREFIX="$WORK/prefix-arm64"
    TRIPLE="aarch64-linux-android$NDK_API"

    build_x264 "$PREFIX" \
      --host=aarch64-linux-android \
      --cross-prefix="$TC/bin/$TRIPLE-" \
      --sysroot="$TC/sysroot"

    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
    PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
    build_ffmpeg "$PREFIX" \
      --target-os=android --arch=aarch64 --cpu=armv8-a \
      --cc="$TC/bin/$TRIPLE-clang" \
      --cxx="$TC/bin/$TRIPLE-clang++" \
      --ar="$TC/bin/llvm-ar" --ranlib="$TC/bin/llvm-ranlib" --strip="$TC/bin/llvm-strip" \
      --sysroot="$TC/sysroot" \
      --enable-cross-compile \
      --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib" \
      --pkg-config-flags=--static

    cp "$FFMPEG_SRC/ffmpeg" "$OUT/ffmpeg-min-arm64"
    "$TC/bin/llvm-strip" "$OUT/ffmpeg-min-arm64"
    ;;

  amd64)
    echo ">> target: native linux/amd64"
    PREFIX="$WORK/prefix-amd64"
    HOST_CC="${HOST_CC:-gcc}"

    build_x264 "$PREFIX" --disable-asm
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
    PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
    build_ffmpeg "$PREFIX" \
      --cc="$HOST_CC" --disable-x86asm \
      --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib" \
      --pkg-config-flags=--static

    cp "$FFMPEG_SRC/ffmpeg" "$OUT/ffmpeg-min-linux-amd64"
    strip "$OUT/ffmpeg-min-linux-amd64"
    ;;
esac

echo
echo "done ->"
ls -lh "$OUT"
