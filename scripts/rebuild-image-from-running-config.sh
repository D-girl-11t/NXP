#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Rebuild linux-imx Image + modules from the BOARD's running .config so
# imx519.ko can load. Do not use imx_v8_defconfig against a stock Yocto Image.
#
# On the board first:
#   zcat /proc/config.gz > /tmp/running.config
# Copy that file to the laptop, then:
#   ./scripts/install-into-kernel.sh ~/linux-imx
#   ./scripts/rebuild-image-from-running-config.sh ~/linux-imx /tmp/running.config
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
KSRC="${1:-}"
RCFG="${2:-}"

if [ -z "$KSRC" ] || [ -z "$RCFG" ] || [ ! -d "$KSRC/drivers/media/i2c" ] || [ ! -f "$RCFG" ]; then
	echo "Usage: $0 /path/to/linux-imx /path/to/running.config" >&2
	exit 1
fi

if [ ! -f "$KSRC/drivers/media/i2c/imx519.c" ]; then
	echo "imx519.c is not in $KSRC — run:" >&2
	echo "  $ROOT/scripts/install-into-kernel.sh $KSRC" >&2
	exit 1
fi

FRAG="$ROOT/configs/imx519.cfg"
if [ -f "$KSRC/arch/arm64/configs/imx519.config" ]; then
	FRAG="$KSRC/arch/arm64/configs/imx519.config"
fi

export ARCH="${ARCH:-arm64}"
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
	echo "Missing ${CROSS_COMPILE}gcc. On Ubuntu: sudo apt install gcc-aarch64-linux-gnu" >&2
	exit 1
fi

cd "$KSRC"
cp -v "$RCFG" .config
./scripts/kconfig/merge_config.sh -m .config "$FRAG"
make olddefconfig

if ! grep -q '^CONFIG_VIDEO_IMX519=m' .config; then
	echo "CONFIG_VIDEO_IMX519 did not enable. Check Kconfig install." >&2
	grep VIDEO_IMX519 .config || true
	exit 1
fi

echo
echo "Building Image + modules + dtbs (LOCALVERSION will follow running.config)."
echo "A dirty linux-imx tree may produce uname with -dirty; that is OK if you"
echo "boot THIS Image and install THESE modules together."
echo
make -j"$(nproc)" Image modules dtbs

echo
echo "Built:"
echo "  $KSRC/arch/arm64/boot/Image"
echo "  $KSRC/arch/arm64/boot/dts/freescale/imx93-11x11-frdm-imx519.dtb"
echo "  $KSRC/drivers/media/i2c/imx519.ko"
echo
echo "On the FRDM, copy Image onto the FAT partition U-Boot already uses"
echo "(same place as imx93-11x11-frdm.dtb), e.g.:"
echo "  cp Image /run/media/boot-mmcblk0p1/Image"
echo "  # backup first: cp Image Image.before-imx519"
echo "Then install modules into the rootfs (from the laptop, with the card mounted):"
echo "  sudo make ARCH=arm64 INSTALL_MOD_PATH=/mnt/root modules_install"
echo "Reboot, then: uname -r && modprobe imx519"
