#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Configure the i.MX93 media graph:
#   imx519 -> mxc-mipi-csi2.0 -> mxc_isi.0 -> /dev/videoN
#
# Usage:
#   setup-pipeline.sh              # 1920x1080 RAW10
#   setup-pipeline.sh 1280 720
#   setup-pipeline.sh 1920 1080 RG10

set -eu

WIDTH="${1:-1920}"
HEIGHT="${2:-1080}"
PIXFMT="${3:-RG10}"
MEDIA="${MEDIA:-/dev/media0}"

if ! command -v media-ctl >/dev/null 2>&1; then
	echo "media-ctl not found. Install v4l-utils." >&2
	exit 1
fi

if [ ! -e "$MEDIA" ]; then
	echo "No $MEDIA. Is the NXP camera media device probed?" >&2
	exit 1
fi

echo "Media graph ($MEDIA):"
media-ctl -d "$MEDIA" -p || true
echo

find_entity() {
	# Print the first entity whose name matches the pattern.
	media-ctl -d "$MEDIA" -p | awk -v pat="$1" '
		$1 == "-entity" || $1 == "entity" { next }
		/^[ \t]*- entity / {
			line = $0
			sub(/^[ \t]*- entity [0-9]+: /, "", line)
			name = line
			sub(/ \(.*/, "", name)
			if (name ~ pat) {
				print name
				exit
			}
		}
		/^entity [0-9]+: / {
			name = $0
			sub(/^entity [0-9]+: /, "", name)
			sub(/ \(.*/, "", name)
			if (name ~ pat) {
				print name
				exit
			}
		}
	'
}

SENSOR="$(find_entity "imx519")"
CSI="$(find_entity "mipi-csi2")"
ISI="$(find_entity "mxc_isi")"

if [ -z "$SENSOR" ]; then
	echo "IMX519 subdev not in the graph. Check:" >&2
	echo "  - Device tree replaced AP1302 with sony,imx519@1a" >&2
	echo "  - dmesg | grep -i imx519" >&2
	echo "  - i2c-probe.sh" >&2
	exit 1
fi

FMT="SRGGB10_1X10/${WIDTH}x${HEIGHT} field:none"

echo "Entities:"
echo "  sensor: $SENSOR"
echo "  csi:    ${CSI:-<not found>}"
echo "  isi:    ${ISI:-<not found>}"
echo "Format:   $FMT"
echo

media-ctl -d "$MEDIA" --set-v4l2 "'${SENSOR}':0[fmt:${FMT}]"

if [ -n "$CSI" ]; then
	# Sink pad 0 and source pad 4 are the usual NXP DWC CSI mapping.
	media-ctl -d "$MEDIA" --set-v4l2 "'${CSI}':0[fmt:${FMT}]" || true
	media-ctl -d "$MEDIA" --set-v4l2 "'${CSI}':4[fmt:${FMT}]" || true
fi

if [ -n "$ISI" ]; then
	media-ctl -d "$MEDIA" --set-v4l2 "'${ISI}':0[fmt:${FMT}]" || true
	media-ctl -d "$MEDIA" --set-v4l2 "'${ISI}':12[fmt:${FMT}]" || true
fi

VIDEO="${VIDEO:-}"
if [ -z "$VIDEO" ]; then
	# Prefer the ISI capture node.
	VIDEO="$(v4l2-ctl --list-devices 2>/dev/null | awk '
		/isi/ || /mxc-isi/ { grab=1; next }
		grab && /\/dev\/video/ { print $1; exit }
	')"
	VIDEO="${VIDEO:-/dev/video0}"
fi

echo "Capture node: $VIDEO"
v4l2-ctl -d "$VIDEO" --set-fmt-video="width=${WIDTH},height=${HEIGHT},pixelformat=${PIXFMT}" || \
	v4l2-ctl -d "$VIDEO" --set-fmt-video="width=${WIDTH},height=${HEIGHT},pixelformat=RG10"

echo
echo "Current video format:"
v4l2-ctl -d "$VIDEO" --get-fmt-video || true

echo
echo "Sensor controls (exposure / gain / test pattern / flips):"
# The sensor subdev node, not the ISI video node.
SUBDEV="$(media-ctl -d "$MEDIA" -p | awk -v name="$SENSOR" '
	index($0, name) { inent=1 }
	inent && /device node name/ { print $NF; exit }
')"
if [ -n "${SUBDEV:-}" ]; then
	echo "  subdev: $SUBDEV"
	v4l2-ctl -d "$SUBDEV" --list-ctrls || true
	echo "$SUBDEV" > /tmp/imx519-subdev
fi
echo "$VIDEO" > /tmp/imx519-video
echo "$WIDTH" > /tmp/imx519-width
echo "$HEIGHT" > /tmp/imx519-height

echo
echo "Pipeline is configured. Capture with scripts/capture-still.sh or capture-video.sh"
