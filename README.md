
# ffmpeg-minimal

A reproducible build recipe that turns the ~347 MB Termux `ffmpeg` into a
**~3–4 MB static binary** containing only what
[OpenCall](https://github.com/Lamprozx/OpenCall) actually uses.

> This repo ships the **build script**, not a fork of ffmpeg. The ffmpeg and
> x264 sources are downloaded by `build.sh` from their official upstreams.

## Why

OpenCall only needs ffmpeg for two things:

1. **Audio effects** (`--speed`, `--pitch`, `--reverb`, `--bass`, …) applied to
   `--play` files.
2. **Video transcoding** (`--video-file`) to baseline H.264.

Plain `--play foo.mp3` already works without ffmpeg (native pure-Go decoding).
But if you do want FX or video, the full Termux ffmpeg pulls in ~70 packages and
~347 MB of disk. This build keeps only the pieces those two paths need, so the
result is ~99% smaller.

## What's included

| Kind     | Components |
|----------|------------|
| Decode   | `mp3`, `wav` (`pcm_s16le`), `opus`, `h264`, `aac` |
| Encode   | `pcm_s16le` (wav) + `libx264` (baseline, 8-bit yuv420p) |
| Filters  | `atempo`, `aecho`, `bass`, `treble`, `lowpass`, `highpass`, `chorus`, `flanger`, `tremolo`, `vibrato`, `acrusher`, `afade`, `areverse`, `asetrate`, `aresample`, `aformat`, `format`, `fps` |
| Demuxers | `mp3`, `wav`, `ogg`, `mov`, `matroska`, `h264`, `aac` |
| Muxers   | `wav`, `h264` |
| Bitstream | `h264_metadata` |

## Build

```bash
./build.sh arm64    # android/arm64 (Termux)  -> out/ffmpeg-min-arm64
./build.sh amd64    # native linux/amd64      -> out/ffmpeg-min-linux-amd64
./build.sh --help   # show usage
```

Run without an argument and it exits with:

```
please insert a valid architecture, look at 'README.md' or use --help.
```

Before downloading anything, the script asks for confirmation (the build needs
~700 MB of disk): `Continue? [y/N]`.

The `arm64` target downloads the Android NDK (`r26d`) automatically. Host build
uses your system `gcc`.

Requirements: `bash`, `curl`, `unzip`, `xz`, `make`, `git`, and a C toolchain.

## Install

Termux:

```bash
cp ffmpeg-min-arm64 "$PREFIX/bin/ffmpeg"
chmod +x "$PREFIX/bin/ffmpeg"
ffmpeg -version
```

VPS / Linux:

```bash
cp ffmpeg-min-linux-amd64 /usr/local/bin/ffmpeg
```

## License

- The resulting `ffmpeg` binary is **GPL-2.0-or-later** (because it links
  `libx264`, which is GPL). If you redistribute the binary, you must also make
  the corresponding source available — this build script does that by pulling
  from upstream.
- This repo's own files (`build.sh`, `README.md`) are MIT.
- Upstream: [FFmpeg](https://ffmpeg.org) (LGPL/GPL) and
  [x264](https://code.videolan.org/videolan/x264) (GPL-2.0).
