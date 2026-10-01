#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copy the IMX519 driver, Kconfig, DTS, and config fragment into a linux-imx tree.
#
# Usage:
#   ./scripts/install-into-kernel.sh /path/to/linux-imx
#
# This copy of kernel/imx519.c must be the i.MX93 6.18 port (single IMAGE_PAD,
# no MEDIA_BUS_FMT_SENSOR_DATA). An old Raspberry Pi / Unicam tree will be rejected.
#
# The target board is FRDM-i.MX93, so the kernel tree must contain
# arch/arm64/boot/dts/freescale/imx93-11x11-frdm.dts (lf-6.12 or later).

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
KSRC="${1:-}"

if [ -z "$KSRC" ] || [ ! -d "$KSRC/drivers/media/i2c" ]; then
	echo "Usage: $0 /path/to/linux-imx" >&2
	exit 1
fi

SRC_C="$ROOT/kernel/imx519.c"
if [ ! -f "$SRC_C" ]; then
	echo "Missing $SRC_C" >&2
	exit 1
fi
if grep -q 'MEDIA_BUS_FMT_SENSOR_DATA' "$SRC_C"; then
	echo "ERROR: $SRC_C is the Raspberry Pi/Unicam driver, not the i.MX93 port." >&2
	echo "Replace kernel/imx519.c from the current Cursor project, then re-run." >&2
	exit 1
fi
if ! grep -q 'i.MX93 CSI/ISI is a single image stream' "$SRC_C"; then
	echo "ERROR: $SRC_C does not look like the i.MX93 single-pad port." >&2
	exit 1
fi

I2C="$KSRC/drivers/media/i2c"
DTS="$KSRC/arch/arm64/boot/dts/freescale"
KCFG="$I2C/Kconfig"
MK="$I2C/Makefile"
DTMK="$DTS/Makefile"

strip_makefile_dtb() {
	# $1 = Makefile, $2 = dtb name
	if [ -f "$1" ] && grep -q "$2" "$1"; then
		grep -v "$2" "$1" > "$1.tmp"
		mv "$1.tmp" "$1"
		echo "Removed $2 from $1"
	fi
}

cp -v "$SRC_C" "$I2C/imx519.c"

# Kconfig: keep CONFIG_VIDEO_IMX519 in its own file and source it, so repeated
# runs refresh one file instead of appending to the kernel's Kconfig.
cp -v "$ROOT/kernel/Kconfig" "$I2C/Kconfig.imx519"
if ! grep -q 'Kconfig.imx519' "$KCFG"; then
	# Source it inside the menu, before the first endmenu, or append if the
	# file has no menu at all.
	if grep -q '^endmenu' "$KCFG"; then
		awk '
			/^endmenu/ && !done {
				print "source \"drivers/media/i2c/Kconfig.imx519\""
				done = 1
			}
			{ print }
		' "$KCFG" > "$KCFG.new"
		mv "$KCFG.new" "$KCFG"
	else
		printf '\nsource "drivers/media/i2c/Kconfig.imx519"\n' >> "$KCFG"
	fi
	echo "Added source of Kconfig.imx519 to $KCFG"
fi

if ! grep -q 'imx519.o' "$MK"; then
	printf '\nobj-$(CONFIG_VIDEO_IMX519) += imx519.o\n' >> "$MK"
	echo "Added imx519.o to $MK"
fi

if [ -f "$DTS/imx93-11x11-frdm.dts" ]; then
	cp -v "$ROOT/dts/imx93-11x11-frdm-imx519.dts" "$DTS/"
else
	echo "ERROR: $DTS/imx93-11x11-frdm.dts not found." >&2
	echo "This does not look like an FRDM-capable linux-imx tree (need lf-6.12 or later)." >&2
	exit 1
fi

if ! grep -q 'imx93-11x11-frdm-imx519.dtb' "$DTMK"; then
	printf '\ndtb-$(CONFIG_ARCH_MXC) += imx93-11x11-frdm-imx519.dtb\n' >> "$DTMK"
	echo "Added imx93-11x11-frdm-imx519.dtb"
fi

# Earlier versions of this script also installed an 11x11 EVK overlay. It was
# never tested and its lf-6.6 variant aborts `make dtbs` on a 6.12+ tree, so
# remove any leftovers from a previously patched kernel.
strip_makefile_dtb "$DTMK" 'imx93-11x11-evk-imx519.dtb'
rm -f "$DTS/imx93-11x11-evk-imx519.dts"

mkdir -p "$KSRC/arch/arm64/configs"
cp -v "$ROOT/configs/imx519.cfg" "$KSRC/arch/arm64/configs/imx519.config"

echo
echo "Installed into $KSRC"
echo "Next — FRDM with a stock Yocto Image: do NOT use imx_v8_defconfig."
echo "  On the board:  zcat /proc/config.gz > /tmp/running.config"
echo "  Copy that file to the laptop, then either:"
echo "    $ROOT/scripts/rebuild-image-from-running-config.sh $KSRC ~/running.config"
echo "  or the same steps by hand (see docs/build-and-flash.md)."
echo "If you will replace Image+modules from defconfig anyway:"
echo "  cd $KSRC && make imx_v8_defconfig"
echo "  ./scripts/kconfig/merge_config.sh -m .config arch/arm64/configs/imx519.config"
echo "  make olddefconfig && make -j\$(nproc) Image dtbs modules"
