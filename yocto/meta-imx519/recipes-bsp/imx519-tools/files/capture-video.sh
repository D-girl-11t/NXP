#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Record N RAW frames (or a timed burst) from the IMX519, then optionally
# wrap them as a video with ffmpeg.
#
# Usage:
#   capture-video.sh                 # 60 frames -> capture.raw
#   capture-video.sh 120 clip.raw
#   FRAMES=30 FPS=30 capture-video.sh
#
# The i.MX93 has no ISP, so this records Bayer RAW. ffmpeg can demosaic
# and encode after the fact.

set -eu

FRAMES="${1:-${FRAMES:-60}}"
OUT="${2:-capture-$(date +%Y%m%d-%H%M%S).raw}"
FPS="${FPS:-30}"
VIDEO="${VIDEO:-}"
ENCODE="${ENCODE:-}"

if [ -z "$VIDEO" ] && [ -f /tmp/imx519-video ]; then
	VIDEO="$(cat /tmp/imx519-video)"
fi
VIDEO="${VIDEO:-/dev/video0}"

WIDTH="${WIDTH:-}"
HEIGHT="${HEIGHT:-}"
if [ -z "$WIDTH" ] && [ -f /tmp/imx519-width ]; then
	WIDTH="$(cat /tmp/imx519-width)"
	HEIGHT="$(cat /tmp/imx519-height)"
fi
WIDTH="${WIDTH:-1920}"
HEIGHT="${HEIGHT:-1080}"

echo "Recording $FRAMES frames from $VIDEO -> $OUT (${WIDTH}x${HEIGHT} @ ~${FPS} fps requested)"
v4l2-ctl -d "$VIDEO" \
	--stream-mmap \
	--stream-count="$FRAMES" \
	--stream-to="$OUT"

SIZE="$(wc -c < "$OUT" | tr -d ' ')"
echo "Wrote $OUT ($SIZE bytes)"

if command -v ffmpeg >/dev/null 2>&1; then
	MP4="${OUT%.raw}.mp4"
	echo "Encoding preview with ffmpeg (bayer_rggb16le) -> $MP4"
	ffmpeg -y -f rawvideo -pix_fmt bayer_rggb16le -s "${WIDTH}x${HEIGHT}" \
		-r "$FPS" -i "$OUT" -vf "format=yuv420p" -c:v libx264 -preset veryfast \
		"$MP4" || echo "ffmpeg encode failed (pixfmt may be packed RG10; try userspace/raw10_to_png.py --video)"
else
	echo "Install ffmpeg to wrap RAW into an MP4, or convert frame-by-frame with userspace/raw10_to_png.py"
fi
