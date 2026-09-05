#!/usr/bin/env python3
"""Convert IMX519 RAW10 captures to PNG (and optional MJPEG video).

i.MX93 ISI typically writes RAW10 into 16-bit little-endian samples
(V4L2_PIX_FMT_SRGGB10 / RG10) with 10 significant bits. Packed MIPI RAW10
(5 bytes per 4 pixels) is also accepted.

Examples:
  python3 raw10_to_png.py --width 1920 --height 1080 frame.raw frame.png
  python3 raw10_to_png.py --layout packed10 --width 1920 --height 1080 cap.raw out.png
  python3 raw10_to_png.py --video --fps 30 --width 1920 --height 1080 capture.raw clip.mp4
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def _require(mod: str, pip: str) -> None:
    try:
        __import__(mod)
    except ImportError as exc:
        raise SystemExit(
            f"Missing {mod}. Install with: pip install {pip}"
        ) from exc


def unpack_raw10_mipi(buf: bytes, width: int, height: int):
    import numpy as np

    stride = (width * 10 + 7) // 8
    expected = stride * height
    if len(buf) < expected:
        raise ValueError(f"buffer is {len(buf)} bytes, need at least {expected} for packed RAW10")
    out = np.zeros((height, width), dtype=np.uint16)
    for y in range(height):
        row = buf[y * stride : (y + 1) * stride]
        x = 0
        i = 0
        while x + 4 <= width and i + 5 <= len(row):
            b0, b1, b2, b3, b4 = row[i : i + 5]
            out[y, x] = b0 | ((b4 & 0x03) << 8)
            out[y, x + 1] = b1 | ((b4 & 0x0C) << 6)
            out[y, x + 2] = b2 | ((b4 & 0x30) << 4)
            out[y, x + 3] = b3 | ((b4 & 0xC0) << 2)
            x += 4
            i += 5
    return out


def load_frame(buf: bytes, width: int, height: int, layout: str):
    import numpy as np

    unpacked = width * height * 2
    packed = ((width * 10 + 7) // 8) * height

    if layout == "auto":
        if len(buf) >= unpacked:
            layout = "unpacked16"
        elif len(buf) >= packed:
            layout = "packed10"
        else:
            raise ValueError(
                f"buffer is {len(buf)} bytes; {width}x{height} unpacked16 needs {unpacked}, packed10 needs {packed}"
            )

    if layout == "unpacked16":
        if len(buf) < unpacked:
            raise ValueError(f"need {unpacked} bytes for unpacked16, got {len(buf)}")
        arr = np.frombuffer(buf[:unpacked], dtype="<u2").reshape((height, width))
        # Keep 10-bit samples; some ISI builds left-align into the top of 16 bits.
        if int(arr.max()) > 1023:
            arr = arr >> 6
        return arr.copy()

    if layout == "packed10":
        return unpack_raw10_mipi(buf, width, height)

    raise ValueError(f"unknown layout {layout}")


def demosaic_rggb(bayer):
    """Bilinear RGGB demosaic. IMX519 reports MEDIA_BUS_FMT_SRGGB10."""
    import numpy as np
    from numpy.lib.stride_tricks import sliding_window_view

    h, w = bayer.shape
    src = bayer.astype(np.float32)
    r = np.zeros((h, w), dtype=np.float32)
    g = np.zeros((h, w), dtype=np.float32)
    b = np.zeros((h, w), dtype=np.float32)

    r[0::2, 0::2] = src[0::2, 0::2]
    g[0::2, 1::2] = src[0::2, 1::2]
    g[1::2, 0::2] = src[1::2, 0::2]
    b[1::2, 1::2] = src[1::2, 1::2]

    kernel = np.array([[0, 1, 0], [1, 0, 1], [0, 1, 0]], dtype=np.float32)
    kdiag = np.array([[1, 0, 1], [0, 0, 0], [1, 0, 1]], dtype=np.float32)

    def conv_fill(ch, missing, k):
        pad = np.pad(ch, 1, mode="edge")
        win = sliding_window_view(pad, (3, 3))
        num = (win * k).sum(axis=(2, 3))
        den = ((win != 0) * k).sum(axis=(2, 3))
        den[den == 0] = 1
        filled = num / den
        out = ch.copy()
        out[missing] = filled[missing]
        return out

    g = conv_fill(g, g == 0, kernel)
    r = conv_fill(r, r == 0, kernel)
    r = conv_fill(r, r == 0, kdiag)
    b = conv_fill(b, b == 0, kernel)
    b = conv_fill(b, b == 0, kdiag)

    rgb = np.stack([r, g, b], axis=-1)
    rgb = np.clip(rgb, 0, 1023)
    return np.clip((rgb / 1023.0) ** (1 / 2.2) * 255.0, 0, 255).astype(np.uint8)


def save_png(rgb, path: Path) -> None:
    """Write an 8-bit RGB PNG using only the standard library."""
    import struct
    import zlib

    height, width, planes = rgb.shape
    if planes != 3:
        raise ValueError("expected HxWx3 RGB")
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(height))

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def iter_frames(data: bytes, width: int, height: int, layout: str):
    unpacked = width * height * 2
    packed = ((width * 10 + 7) // 8) * height
    frame_size = unpacked if layout in ("auto", "unpacked16") and len(data) >= unpacked else packed
    if layout == "unpacked16":
        frame_size = unpacked
    elif layout == "packed10":
        frame_size = packed
    elif len(data) >= unpacked:
        frame_size = unpacked
        layout = "unpacked16"
    else:
        frame_size = packed
        layout = "packed10"

    n = max(len(data) // frame_size, 1)
    for i in range(n):
        chunk = data[i * frame_size : (i + 1) * frame_size]
        if len(chunk) < frame_size:
            break
        yield load_frame(chunk, width, height, layout)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("raw")
    p.add_argument("out")
    p.add_argument("--width", type=int, default=1920)
    p.add_argument("--height", type=int, default=1080)
    p.add_argument("--layout", choices=("auto", "unpacked16", "packed10"), default="auto")
    p.add_argument("--video", action="store_true", help="treat input as a concatenation of frames")
    p.add_argument("--fps", type=int, default=30)
    args = p.parse_args()

    _require("numpy", "numpy")
    data = Path(args.raw).read_bytes()

    if args.video:
        _require("cv2", "opencv-python-headless")
        import cv2

        frames = list(iter_frames(data, args.width, args.height, args.layout))
        if not frames:
            raise SystemExit("no frames decoded")
        rgb0 = demosaic_rggb(frames[0])
        h, w, _ = rgb0.shape
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        writer = cv2.VideoWriter(args.out, fourcc, args.fps, (w, h))
        writer.write(cv2.cvtColor(rgb0, cv2.COLOR_RGB2BGR))
        for bayer in frames[1:]:
            rgb = demosaic_rggb(bayer)
            writer.write(cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR))
        writer.release()
        print(f"wrote {len(frames)} frames to {args.out}")
        return 0

    bayer = load_frame(data, args.width, args.height, args.layout)
    rgb = demosaic_rggb(bayer)
    save_png(rgb, Path(args.out))
    print(f"wrote {args.out} ({args.width}x{args.height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
