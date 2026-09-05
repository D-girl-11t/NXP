#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Move the Arducam IMX519 voice-coil (AK7375) focus.
#
# Usage:
#   focus.sh              # print current focus control
#   focus.sh 512          # set absolute focus (range depends on AK7375)
#   focus.sh +64          # relative step
#   focus.sh auto         # try V4L2_CID_FOCUS_AUTO if the VCM driver exposes it

set -eu

VAL="${1:-}"
MEDIA="${MEDIA:-/dev/media0}"

find_vcm() {
	media-ctl -d "$MEDIA" -p 2>/dev/null | awk '
		/ak7375|dw9714|ad5820|VCM|vcm/ { inent=1 }
		inent && /device node name/ { print $NF; exit }
	'
}

# Fallback: scan subdevs for focus_absolute.
if [ -z "${VCM:-}" ]; then
	VCM="$(find_vcm || true)"
fi
if [ -z "${VCM:-}" ]; then
	for n in /dev/v4l-subdev*; do
		[ -e "$n" ] || continue
		if v4l2-ctl -d "$n" --list-ctrls 2>/dev/null | grep -q focus_absolute; then
			VCM="$n"
			break
		fi
	done
fi

if [ -z "${VCM:-}" ]; then
	echo "No focus control found. Enable CONFIG_VIDEO_AK7375 and the ak7375@c DT node." >&2
	exit 1
fi

echo "VCM subdev: $VCM"
v4l2-ctl -d "$VCM" --list-ctrls | grep -i focus || true

if [ -z "$VAL" ]; then
	v4l2-ctl -d "$VCM" --get-ctrl=focus_absolute || true
	exit 0
fi

if [ "$VAL" = "auto" ]; then
	v4l2-ctl -d "$VCM" --set-ctrl=focus_automatic_continuous=1 || \
		v4l2-ctl -d "$VCM" --set-ctrl=focus_auto=1 || \
		{ echo "This VCM driver is manual-only. Pass a DAC value, e.g. $0 512"; exit 1; }
	exit 0
fi

case "$VAL" in
	+*|-*)
		CUR="$(v4l2-ctl -d "$VCM" --get-ctrl=focus_absolute | awk -F: '{gsub(/ /,""); print $2}')"
		NEXT=$((CUR + VAL))
		v4l2-ctl -d "$VCM" --set-ctrl="focus_absolute=${NEXT}"
		;;
	*)
		v4l2-ctl -d "$VCM" --set-ctrl="focus_absolute=${VAL}"
		;;
esac

v4l2-ctl -d "$VCM" --get-ctrl=focus_absolute
