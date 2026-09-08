#!/usr/bin/env python3
"""Capture stills and video from an Arducam IMX519 on NXP i.MX93.

The sensor outputs 10-bit Bayer (SRGGB). i.MX93 has no hardware ISP, so this
tool demosaics in software after a V4L2 capture.

Examples:
  ./imx519_capture.py --jpeg still.jpg
  ./imx519_capture.py --jpeg still.jpg --autofocus
  ./imx519_capture.py --mp4 clip.mp4 --seconds 5 --fps 30
  ./imx519_capture.py --from-raw frame.raw --width 1920 --height 1080 --jpeg out.jpg
"""
from __future__ import annotations

import argparse
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    print("+", " ".join(cmd), file=sys.stderr)
    return subprocess.run(cmd, check=check, text=True, capture_output=True)


def setup_pipeline(width: int, height: int) -> str:
    subprocess.run(["/bin/sh", str(script), str(width), str(height)], check=True)
    video = Path("/tmp/imx519-video").read_text().strip()
    return video


def list_subdev_focus() -> tuple[str, str] | None:
    """Return (device, control_name) for the VCM focus control if present."""
    if not shutil.which("v4l2-ctl"):
        return None
    for node in sorted(Path("/dev").glob("v4l-subdev*")):
        proc = subprocess.run(
            ["v4l2-ctl", "-d", str(node), "-l"],
            text=True,
            capture_output=True,
        )
        if proc.returncode != 0:
            continue
        for line in proc.stdout.splitlines():
            name = line.strip().split()[0] if line.strip() else ""
            if "focus_absolute" in name or name == "focus":
                return str(node), name
    return None


def set_focus(pos: int) -> None:
    found = list_subdev_focus()
    if not found:
        raise SystemExit("no V4L2 focus control found (is ak7375 loaded?)")
    dev, name = found
    run(["v4l2-ctl", "-d", dev, "-c", f"{name}={pos}"])


def get_focus_range() -> tuple[int, int]:
    found = list_subdev_focus()
    if not found:
        return 0, 4095
    dev, name = found
    proc = run(["v4l2-ctl", "-d", dev, "-l"], check=False)
    lo, hi = 0, 4095
    for line in proc.stdout.splitlines():
        if name not in line:
            continue
        for tok in line.replace(":", " ").replace("=", " ").split():
            if tok.startswith("min="):
                lo = int(tok.split("=")[1])
            if tok.startswith("max="):
                hi = int(tok.split("=")[1])
    return lo, hi


def capture_raw(video: str, width: int, height: int, path: Path, frames: int = 1) -> None:
    cmd = [
        "v4l2-ctl",
        "-d",
        video,
        f"--set-fmt-video=width={width},height={height},pixelformat=RG10",
        "--stream-mmap",
        f"--stream-count={frames}",
        f"--stream-to={path}",
    ]
    proc = subprocess.run(cmd, text=True, capture_output=True)
    if proc.returncode != 0:
        cmd[3] = f"--set-fmt-video=width={width},height={height},pixelformat=BA10"
        proc = subprocess.run(cmd, text=True, capture_output=True)
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        raise SystemExit("v4l2-ctl capture failed")


def unpack_raw10(data: bytes, width: int, height: int):
    pixels = width * height
    unpacked = pixels * 2
    packed = (pixels * 10 + 7) // 8
    if len(data) >= unpacked and len(data) % unpacked == 0:
        frame = data[:unpacked]
        return [struct.unpack_from("<H", frame, i * 2)[0] & 0x3FF for i in range(pixels)]
    if len(data) >= packed:
        frame = data[:packed]
        out = []
        i = 0
        while len(out) < pixels and i + 5 <= len(frame):
            b0, b1, b2, b3, b4 = frame[i : i + 5]
            out.extend(
                [
                    b0 | ((b1 & 0x03) << 8),
                    ((b1 >> 2) & 0x3F) | ((b2 & 0x0F) << 6),
                    ((b2 >> 4) & 0x0F) | ((b3 & 0x3F) << 4),
                    ((b3 >> 6) & 0x03) | (b4 << 2),
                ]
            )
            i += 5
        return out[:pixels]
    raise SystemExit(
        f"unexpected RAW size {len(data)} for {width}x{height} "
        f"(expected {unpacked} unpacked or ~{packed} packed)"
    )


def demosaic_rggb(raw: list[int], width: int, height: int) -> bytes:
    def at(x: int, y: int) -> int:
        x = min(max(x, 0), width - 1)
        y = min(max(y, 0), height - 1)
        return raw[y * width + x]

    rgb = bytearray(width * height * 3)
    for y in range(height):
        row = y * width * 3
        for x in range(width):
            even_x = (x & 1) == 0
            even_y = (y & 1) == 0
            if even_y and even_x:
                r = at(x, y)
                g = (at(x + 1, y) + at(x - 1, y) + at(x, y + 1) + at(x, y - 1)) // 4
                b = (at(x + 1, y + 1) + at(x - 1, y + 1) + at(x + 1, y - 1) + at(x - 1, y - 1)) // 4
            elif even_y and not even_x:
                g = at(x, y)
                r = (at(x - 1, y) + at(x + 1, y)) // 2
                b = (at(x, y - 1) + at(x, y + 1)) // 2
            elif not even_y and even_x:
                g = at(x, y)
                b = (at(x - 1, y) + at(x + 1, y)) // 2
                r = (at(x, y - 1) + at(x, y + 1)) // 2
            else:
                b = at(x, y)
                g = (at(x + 1, y) + at(x - 1, y) + at(x, y + 1) + at(x, y - 1)) // 4
                r = (at(x + 1, y + 1) + at(x - 1, y + 1) + at(x + 1, y - 1) + at(x - 1, y - 1)) // 4
            o = row + x * 3
            rgb[o] = min(255, r >> 2)
            rgb[o + 1] = min(255, g >> 2)
            rgb[o + 2] = min(255, b >> 2)
    return bytes(rgb)


def save_jpeg(rgb: bytes, width: int, height: int, path: Path) -> None:
    try:
        from PIL import Image
    except ImportError:
        ppm = path.with_suffix(".ppm")
        with ppm.open("wb") as f:
            f.write(f"P6\n{width} {height}\n255\n".encode("ascii"))
            f.write(rgb)
        print(f"Pillow not installed; wrote {ppm}.  pip3 install pillow  to get JPEG.")
        return
    img = Image.frombytes("RGB", (width, height), rgb)
    img.save(path, quality=92)
    print(f"wrote {path}")


def sharpness(rgb: bytes, width: int, height: int) -> float:
    # Downsampled Laplacian energy — good enough for contrast AF.
    step = 8
    acc = 0.0
    n = 0
    def lum(x: int, y: int) -> int:
        o = (y * width + x) * 3
        return rgb[o] + rgb[o + 1] + rgb[o + 2]

    for y in range(step, height - step, step):
        for x in range(step, width - step, step):
            c = lum(x, y)
            lap = abs(4 * c - lum(x - step, y) - lum(x + step, y) - lum(x, y - step) - lum(x, y + step))
            acc += lap
            n += 1
    return acc / max(n, 1)


def raw_to_rgb(data: bytes, width: int, height: int) -> bytes:
    return demosaic_rggb(unpack_raw10(data, width, height), width, height)


def autofocus(video: str, width: int, height: int) -> int:
    lo, hi = get_focus_range()
    steps = 12
    best_pos, best_score = lo, -1.0
    print(f"contrast AF sweep {lo}..{hi} ({steps} steps)", file=sys.stderr)
    with tempfile.TemporaryDirectory() as td:
        raw_path = Path(td) / "af.raw"
        for i in range(steps):
            pos = lo + (hi - lo) * i // (steps - 1)
            set_focus(pos)
            capture_raw(video, width, height, raw_path, frames=1)
            rgb = raw_to_rgb(raw_path.read_bytes(), width, height)
            score = sharpness(rgb, width, height)
            print(f"  focus={pos:4d}  score={score:.1f}", file=sys.stderr)
            if score > best_score:
                best_pos, best_score = pos, score
    set_focus(best_pos)
    print(f"selected focus={best_pos}", file=sys.stderr)
    return best_pos


def encode_mp4(raw_path: Path, width: int, height: int, fps: int, out: Path) -> None:
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg is required for --mp4")
    cmd = [
        "ffmpeg",
        "-y",
        "-f",
        "rawvideo",
        "-pixel_format",
        "bayer_rggb16le",
        "-s",
        f"{width}x{height}",
        "-r",
        str(fps),
        "-i",
        str(raw_path),
        "-vf",
        "format=yuv420p",
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        str(out),
    ]
    proc = subprocess.run(cmd)
    if proc.returncode != 0:
        raise SystemExit("ffmpeg encode failed")
    print(f"wrote {out}")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--width", type=int, default=1920)
    p.add_argument("--height", type=int, default=1080)
    p.add_argument("--device", help="capture node, default: auto via setup-pipeline.sh")
    p.add_argument("--jpeg", type=Path, help="write a demosaiced JPEG (or PPM)")
    p.add_argument("--raw", type=Path, help="keep the captured RAW dump")
    p.add_argument("--from-raw", type=Path, help="demosaic an existing RAW file")
    p.add_argument("--mp4", type=Path, help="record video to MP4")
    p.add_argument("--seconds", type=float, default=5.0)
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--autofocus", action="store_true", help="contrast AF before still capture")
    p.add_argument("--focus", type=int, help="set VCM focus position (0-4095)")
    p.add_argument("--skip-pipeline", action="store_true")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    if args.from_raw:
        rgb = raw_to_rgb(args.from_raw.read_bytes(), args.width, args.height)
        if args.jpeg:
            save_jpeg(rgb, args.width, args.height, args.jpeg)
        return 0

    if not shutil.which("v4l2-ctl"):
        raise SystemExit("v4l2-ctl is required (package v4l-utils)")

    video = args.device
    if not video:
        if args.skip_pipeline:
            raise SystemExit("--device is required with --skip-pipeline")
        video = setup_pipeline(args.width, args.height)

    if args.focus is not None:
        set_focus(args.focus)

    if args.autofocus:
        autofocus(video, args.width, args.height)

    if args.mp4:
        frames = max(1, int(args.seconds * args.fps))
        with tempfile.NamedTemporaryFile(suffix=".raw", delete=False) as tmp:
            raw_path = Path(tmp.name)
        try:
            capture_raw(video, args.width, args.height, raw_path, frames=frames)
            if args.raw:
                shutil.copy(raw_path, args.raw)
            encode_mp4(raw_path, args.width, args.height, args.fps, args.mp4)
        finally:
            raw_path.unlink(missing_ok=True)
        return 0

    if not args.jpeg and not args.raw:
        args.jpeg = Path("capture.jpg")

    with tempfile.NamedTemporaryFile(suffix=".raw", delete=False) as tmp:
        raw_path = Path(tmp.name)
    try:
        capture_raw(video, args.width, args.height, raw_path, frames=1)
        data = raw_path.read_bytes()
        if args.raw:
            shutil.copy(raw_path, args.raw)
            print(f"wrote {args.raw}")
        if args.jpeg:
            save_jpeg(raw_to_rgb(data, args.width, args.height), args.width, args.height, args.jpeg)
    finally:
        raw_path.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
