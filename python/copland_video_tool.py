#!/usr/bin/env python3
"""Render a shrinking, center-sampled pixel grid from a still image."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import imageio_ffmpeg
from PIL import Image, ImageChops, ImageDraw


class HelpOnErrorParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.print_help()
        self.exit(2, f"\nerror: {message}\n")


def parse_color(value: str) -> tuple[int, int, int]:
    value = value.removeprefix("#")
    if len(value) != 6:
        raise argparse.ArgumentTypeError("color must be RRGGBB")
    try:
        return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))
    except ValueError as exc:
        raise argparse.ArgumentTypeError("color must be RRGGBB") from exc


def parse_keyframes(value: str) -> list[tuple[float, float]]:
    try:
        points = []
        for item in value.split(","):
            time, size = item.split(":", 1)
            points.append((float(time), float(size)))
        if len(points) < 2 or points[0][0] != 0 or points[-1][1] != 1:
            raise ValueError("keyframes must start at time 0 and end at size 1")
        if any(not math.isfinite(t) or not math.isfinite(s) or t < 0 or s < 1 for t, s in points):
            raise ValueError("times and sizes must be finite; times nonnegative, sizes at least 1")
        if any(b[0] <= a[0] or b[1] > a[1] for a, b in zip(points, points[1:])):
            raise ValueError("times must increase and sizes must not increase")
        return points
    except ValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc


def choose_box(image: Image.Image, specification: str, threshold: int) -> tuple[int, int, int, int]:
    width, height = image.size
    if specification == "full":
        return (0, 0, width, height)
    if specification == "auto":
        alpha = image.getchannel("A") if "A" in image.getbands() else None
        if alpha is not None and alpha.getextrema()[0] < 255:
            box = alpha.point(lambda v: 255 if v > 0 else 0).getbbox()
        else:
            rgb = image.convert("RGB")
            background = Image.new("RGB", image.size, rgb.getpixel((0, 0)))
            difference = ImageChops.difference(rgb, background).convert("L")
            box = difference.point(lambda v: 255 if v > threshold else 0).getbbox()
        if box is None:
            raise ValueError("auto box found no visible content; use --bbox full")
        return box
    try:
        x0, y0, x1, y1 = (int(part) for part in specification.split(","))
    except ValueError as exc:
        raise ValueError("bbox must be full, auto, or x0,y0,x1,y1") from exc
    if not (0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height):
        raise ValueError("bbox must lie within the image and have positive size")
    return (x0, y0, x1, y1)


def frame_at_size(
    source: Image.Image,
    base: Image.Image,
    box: tuple[int, int, int, int],
    size: int,
) -> Image.Image:
    if size <= 1:
        return source.copy()
    frame = base.copy()
    draw = ImageDraw.Draw(frame)
    x0, y0, x1, y1 = box
    for y in range(y0, y1, size):
        bottom = min(y + size, y1)
        cy = (y + bottom - 1) // 2
        for x in range(x0, x1, size):
            right = min(x + size, x1)
            cx = (x + right - 1) // 2
            draw.rectangle((x, y, right - 1, bottom - 1), fill=source.getpixel((cx, cy)))
    return frame


def size_at_time(
    time: float,
    duration: float,
    start_size: int,
    easing: str,
    keyframes: list[tuple[float, float]] | None,
) -> int:
    return max(1, round(continuous_size_at_time(time, duration, start_size, easing, keyframes)))


def continuous_size_at_time(
    time: float,
    duration: float,
    start_size: int,
    easing: str,
    keyframes: list[tuple[float, float]] | None,
) -> float:
    if keyframes is not None:
        if time >= keyframes[-1][0]:
            return 1.0
        for (t0, s0), (t1, s1) in zip(keyframes, keyframes[1:]):
            if time <= t1:
                amount = (time - t0) / (t1 - t0)
                return max(1.0, s0 + amount * (s1 - s0))
        return 1.0
    progress = min(1.0, time / duration)
    if easing == "geometric":
        return start_size ** (1 - progress)
    if easing == "linear":
        finish_duration = min(1.8, duration * 0.2)
        finish_start = duration - finish_duration
        ratio = finish_start / finish_duration
        low, high = 1.0, float(start_size)
        for _ in range(40):
            middle = (low + high) * 0.5
            if middle * (1 + ratio * math.log(middle)) < start_size:
                low = middle
            else:
                high = middle
        join_size = (low + high) * 0.5
        if time < finish_start:
            return start_size + (join_size - start_size) * time / finish_start
        remaining = max(0.0, (duration - time) / finish_duration)
        return join_size ** remaining
    if easing == "slow-then-fast":
        progress = progress * progress
    elif easing == "fast-then-slow":
        progress = 1 - (1 - progress) ** 2
    return max(1.0, start_size + progress * (1 - start_size))


def smooth_frame_at_size(
    source: Image.Image,
    base: Image.Image,
    box: tuple[int, int, int, int],
    size: float,
    cache: dict[int, Image.Image],
) -> Image.Image:
    lower = math.floor(size)
    blend = size - lower
    needed = {lower, lower + 1} if blend else {lower}
    for obsolete in cache.keys() - needed:
        del cache[obsolete]
    for tile_size in needed - cache.keys():
        cache[tile_size] = frame_at_size(source, base, box, tile_size)
    frame = cache[lower]
    if blend == 0:
        return frame
    return Image.blend(frame, cache[lower + 1], blend)


def positive_float(value: str) -> float:
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("must be a positive finite number")
    return number


def nonnegative_float(value: str) -> float:
    number = float(value)
    if not math.isfinite(number) or number < 0:
        raise argparse.ArgumentTypeError("must be a nonnegative finite number")
    return number


def positive_int(value: str) -> int:
    try:
        number = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be a positive integer") from exc
    if number < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return number


def threshold_value(value: str) -> int:
    try:
        number = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be an integer from 0 to 255") from exc
    if not 0 <= number <= 255:
        raise argparse.ArgumentTypeError("must be an integer from 0 to 255")
    return number


def main() -> None:
    parser = HelpOnErrorParser(prog="copland_video_tool", description=__doc__, allow_abbrev=False)
    parser.add_argument("image", type=Path, help="final PNG/JPEG/etc. image")
    parser.add_argument("output", nargs="?", type=Path, help="output MP4 path (default: next to image)")
    parser.add_argument("-o", "--output", dest="output_option", type=Path, metavar="PATH", help="override the output MP4 path")
    parser.add_argument("--duration", type=positive_float, default=9.0, metavar="SECONDS", help="animation seconds (default: 9)")
    parser.add_argument("--fps", type=positive_float, default=30.0, metavar="RATE", help="video frame rate (default: 30)")
    parser.add_argument("--blank", type=nonnegative_float, default=0.1, metavar="SECONDS", help="blank lead-in seconds (default: 0.1)")
    parser.add_argument("--hold", type=nonnegative_float, default=1.0, metavar="SECONDS", help="final-image hold seconds (default: 1)")
    parser.add_argument("--start-size", type=positive_int, metavar="PIXELS", help="initial tile side length (default: box's larger side)")
    parser.add_argument("--easing", choices=("linear", "geometric", "slow-then-fast", "fast-then-slow"), default="linear", help="tile-size curve (default: linear)")
    parser.add_argument("--keyframes", type=parse_keyframes, metavar="TIME:SIZE,...", help="time:size pairs, e.g. 0:350,5:100,9:1; overrides duration/easing")
    parser.add_argument("--bbox", default="full", metavar="BOX", help="full, auto, or x0,y0,x1,y1 (default: full)")
    parser.add_argument("--threshold", type=threshold_value, default=20, metavar="0..255", help="background difference for --bbox auto (default: 20)")
    parser.add_argument("--background", type=parse_color, metavar="RRGGBB", help="blank-area color (default: upper-left pixel)")
    args = parser.parse_intermixed_args()
    if args.output is not None and args.output_option is not None:
        parser.error("use either positional output or --output, not both")
    output = args.output_option or args.output or args.image.with_suffix(".mp4")

    try:
        with Image.open(args.image) as opened:
            original = opened.copy()
    except (OSError, ValueError) as exc:
        parser.error(f"cannot read image: {exc}")
    if original.mode == "P" and "transparency" in original.info:
        original = original.convert("RGBA")
    if args.background is not None:
        background = args.background
    elif "A" in original.getbands() and original.getchannel("A").getpixel((0, 0)) == 0:
        background = (255, 255, 255)
    else:
        background = original.convert("RGB").getpixel((0, 0))
    try:
        box = choose_box(original, args.bbox, args.threshold)
    except ValueError as exc:
        parser.error(str(exc))
    if "A" in original.getbands():
        canvas = Image.new("RGBA", original.size, (*background, 255))
        source = Image.alpha_composite(canvas, original.convert("RGBA")).convert("RGB")
    else:
        source = original.convert("RGB")
    x0, y0, x1, y1 = box
    base = source.copy()
    ImageDraw.Draw(base).rectangle((x0, y0, x1 - 1, y1 - 1), fill=background)

    start_size = args.start_size or max(x1 - x0, y1 - y0)
    duration = args.keyframes[-1][0] if args.keyframes else args.duration
    if duration <= 0:
        parser.error("animation duration must be positive")
    if args.image.resolve() == output.resolve():
        parser.error("input and output must be different files")

    products = (args.blank * args.fps, duration * args.fps, args.hold * args.fps)
    if not all(math.isfinite(product) for product in products):
        parser.error("duration and fps would create too many frames")
    blank_frames = round(products[0])
    animation_frames = max(2, math.ceil(products[1]) + 1)
    hold_frames = round(products[2])
    if blank_frames + animation_frames + hold_frames > 10_000_000:
        parser.error("duration and fps would create too many frames")
    output.parent.mkdir(parents=True, exist_ok=True)

    width, height = source.size
    encoded_size = (width + width % 2, height + height % 2)
    if encoded_size != source.size:
        padded = Image.new("RGB", encoded_size, background)
    else:
        padded = None

    writer = imageio_ffmpeg.write_frames(
        str(output), encoded_size, fps=args.fps, codec="libx264",
        pix_fmt_in="rgb24", pix_fmt_out="yuv420p", quality=9,
        macro_block_size=1, ffmpeg_log_level="error",
    )
    writer.send(None)

    def write_frame(frame: Image.Image) -> None:
        if padded is not None:
            padded.paste(frame, (0, 0))
            frame = padded
        writer.send(frame.tobytes())

    try:
        for _ in range(blank_frames):
            write_frame(base)
        last_size = None
        last_frame = None
        smooth_cache: dict[int, Image.Image] = {}
        for index in range(animation_frames):
            time = min(index / args.fps, duration)
            if index == animation_frames - 1:
                time = duration
            exact_size = continuous_size_at_time(time, duration, start_size, args.easing, args.keyframes)
            if args.keyframes is None and exact_size <= 16:
                last_frame = smooth_frame_at_size(source, base, box, exact_size, smooth_cache)
                last_size = None
            else:
                size = max(1, round(exact_size))
                if size != last_size:
                    last_frame = frame_at_size(source, base, box, size)
                    last_size = size
            write_frame(last_frame)
        for _ in range(hold_frames):
            write_frame(source)
    finally:
        writer.close()
    print(f"Wrote {output} ({encoded_size[0]}x{encoded_size[1]}, {blank_frames + animation_frames + hold_frames} frames)")


if __name__ == "__main__":
    main()
