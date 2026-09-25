# Copland Video Tool

Create an MP4 from a still image by rendering progressively smaller square color tiles until the full image appears. The Python and compiled macOS commands accept the same arguments and use the same defaults.

## 1. Install prerequisites

**Compiled macOS tool:** A prebuilt `copland_video_tool` needs no installed packages on the Mac where it runs. To compile it yourself, install Apple's Xcode Command Line Tools once on the build Mac:

```sh
xcode-select --install
```

**Python tool:** Python 3.14 (tested here) and the packages in `requirements.txt` are required. The pinned dependencies are Pillow 12.3.0 for image processing and imageio-ffmpeg 0.6.0 for MP4 encoding. Install them in a virtual environment:

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

## 2. Compile the macOS tool

From the project directory, run:

```sh
make
```

This creates `copland_video_tool` in the project directory as a universal Intel/Apple Silicon executable targeting macOS 11 or later. The C animation core is in `core/`; the Objective-C command-line and video code is in `macos/`. The target Mac needs neither Python nor a compiler.

The build is not Developer ID-signed or notarized. For frictionless distribution of a downloaded binary to other Macs, sign and notarize it with an Apple Developer ID before distribution.

## 3. Run

The image path is the only required argument. By default, the MP4 is saved beside the image with the same basename. For example, `my.png` produces `my.mp4`:

```sh
./copland_video_tool "/path/to/my.png"
python3 python/copland_video_tool.py "/path/to/my.png"
```

The defaults are a 9-second reveal at 30 fps, preceded by 0.1 seconds of blank
screen and followed by a 1-second hold on the completed image.

Both commands also accept the same optional arguments:

```sh
./copland_video_tool Mac.png --duration 9 --fps 30 --bbox auto
python3 python/copland_video_tool.py Mac.png --duration 9 --fps 30 --bbox auto
```

Use `-o /path/to/video.mp4` to choose another output path. A second positional output path is supported for compatibility with the original Python command. `python3 pixel_reveal.py ...` continues to work. Run either command with `-h` to see every option; invalid arguments also display the help page. `--keyframes` overrides `--duration` and `--easing` for the animation schedule.

The default `--easing linear` reduces tile side length linearly through most of the
reveal. It uses the last 1.8 seconds (or 20% for shorter animations) for a geometric
finish. The two segments meet at the same speed, and neighboring tile sizes up to
16 pixels are blended across frames so the final 3-to-2-to-1-pixel steps do not flicker.
`--easing geometric` remains available to reveal recognizable detail earlier.
`--keyframes` continues to use its specified timing and integer tile sizes.

Both implementations generate the same tile geometry and frame timing. Their compressed colors can differ, especially on dithered images: Python uses FFmpeg/libx264 and macOS uses AVFoundation's H.264 encoder.

To invoke the compiled tool as `copland_video_tool` without `./` from any directory, put it in a directory on your shell's `PATH`. Running `./copland_video_tool` from this folder requires no installation.

Proudly generated with ChatGPT
