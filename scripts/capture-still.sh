#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Grab one RAW10 still from the IMX519 on i.MX93.
#
# Usage:
#   capture-still.sh                 # frame-0001.raw at current pipeline size
#   capture-still.sh shot.raw
#   capture-still.sh shot.raw 1      # enable colour-bar test pattern
#   TEST_PATTERN=1 capture-still.sh

set -eu

OUT="${1:-frame-$(date +%Y%m%d-%H%M%S).raw}"
PATTERN="${2:-${TEST_PATTERN:-0}}"
VIDEO="${VIDEO:-}"
SUBDEV="${SUBDEV:-}"

if [ -z "$VIDEO" ] && [ -f /tmp/imx519-video ]; then
	VIDEO="$(cat /tmp/imx519-video)"
fi
VIDEO="${VIDEO:-/dev/video0}"

if [ -z "$SUBDEV" ] && [ -f /tmp/imx519-subdev ]; then
	SUBDEV="$(cat /tmp/imx519-subdev)"
fi

if [ ! -e "$VIDEO" ]; then
	echo "No $VIDEO. Run scripts/setup-pipeline.sh first." >&2
	exit 1
fi

if [ "$PATTERN" != "0" ] && [ -n "${SUBDEV:-}" ]; then
	echo "Enabling test pattern $PATTERN on $SUBDEV"
	v4l2-ctl -d "$SUBDEV" --set-ctrl="test_pattern=${PATTERN}" || true
fi

echo "Capturing 1 frame from $VIDEO -> $OUT"
v4l2-ctl -d "$VIDEO" \
	--stream-mmap \
	--stream-count=1 \
	--stream-to="$OUT"

SIZE="$(wc -c < "$OUT" | tr -d ' ')"
echo "Wrote $OUT ($SIZE bytes)"

WIDTH="${WIDTH:-}"
HEIGHT="${HEIGHT:-}"
if [ -z "$WIDTH" ] && [ -f /tmp/imx519-width ]; then
	WIDTH="$(cat /tmp/imx519-width)"
	HEIGHT="$(cat /tmp/imx519-height)"
fi
WIDTH="${WIDTH:-1920}"
HEIGHT="${HEIGHT:-1080}"

echo
echo "Convert to PNG (unpacked 16-bit RGGB10, typical i.MX93 ISI output):"
echo "  python3 userspace/raw10_to_png.py --width $WIDTH --height $HEIGHT --layout unpacked16 $OUT ${OUT%.raw}.png"
echo
echo "Or with ffmpeg (if the node delivers 16-bit Bayer):"
echo "  ffmpeg -f rawvideo -pix_fmt bayer_rggb16le -s ${WIDTH}x${HEIGHT} -i $OUT ${OUT%.raw}.png"

if [ "$PATTERN" != "0" ] && [ -n "${SUBDEV:-}" ]; then
	v4l2-ctl -d "$SUBDEV" --set-ctrl=test_pattern=0 || true
fi
