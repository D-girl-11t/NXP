#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copy tree files into the Yocto layer's file:// directories so bitbake can
# find them without duplicating sources by hand.

set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
LAYER="$ROOT/yocto/meta-imx519"
K="$LAYER/recipes-kernel/linux/linux-imx"
T="$LAYER/recipes-bsp/imx519-tools/files"

mkdir -p "$K" "$T"

cp -v "$ROOT/kernel/imx519.c" "$K/imx519.c"
cp -v "$ROOT/kernel/Kconfig" "$K/Kconfig.imx519"
cp -v "$ROOT/configs/imx519.cfg" "$K/imx519.cfg"
cp -v "$ROOT/dts/imx93-11x11-frdm-imx519.dts" "$K/imx93-11x11-frdm-imx519.dts"
cp -v "$ROOT/userspace/imx519_capture.py" "$T/"

cp -v "$ROOT/scripts/setup-pipeline.sh" "$T/"
cp -v "$ROOT/scripts/capture-still.sh" "$T/"
cp -v "$ROOT/scripts/capture-video.sh" "$T/"
cp -v "$ROOT/scripts/focus.sh" "$T/"
cp -v "$ROOT/scripts/i2c-probe.sh" "$T/"
cp -v "$ROOT/userspace/raw10_to_png.py" "$T/"

echo "Yocto file:// payloads updated."
