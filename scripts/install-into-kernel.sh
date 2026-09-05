#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copy the IMX519 driver, Kconfig, DTS, and config fragment into a linux-imx tree.
#
# Usage:
#   ./scripts/install-into-kernel.sh /path/to/linux-imx
#
# Then in that tree:
#   merge the fragment:  scripts/kconfig/merge_config.sh -m .config ../../configs/imx519.cfg
#   or manually enable CONFIG_VIDEO_IMX519=m and CONFIG_VIDEO_AK7375=m

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
KSRC="${1:-}"

if [ -z "$KSRC" ] || [ ! -d "$KSRC/drivers/media/i2c" ]; then
	echo "Usage: $0 /path/to/linux-imx" >&2
	exit 1
fi

I2C="$KSRC/drivers/media/i2c"
DTS="$KSRC/arch/arm64/boot/dts/freescale"
KCFG="$I2C/Kconfig"
MK="$I2C/Makefile"
DTMK="$DTS/Makefile"

cp -v "$ROOT/kernel/imx519.c" "$I2C/imx519.c"

if ! grep -q 'VIDEO_IMX519' "$KCFG"; then
	# Insert before the last endmenu if present, otherwise append.
	if grep -q '^endmenu' "$KCFG"; then
		awk '
			BEGIN { done=0 }
			/^endmenu/ && !done {
				print "source \"drivers/media/i2c/Kconfig.imx519\""
				done=1
			}
			{ print }
		' "$KCFG" > "$KCFG.new"
		mv "$KCFG.new" "$KCFG"
		cp "$ROOT/kernel/Kconfig" "$I2C/Kconfig.imx519"
		echo "Added source of Kconfig.imx519"
	else
		cat "$ROOT/kernel/Kconfig" >> "$KCFG"
		echo "Appended IMX519 Kconfig"
	fi
fi

if ! grep -q 'imx519.o' "$MK"; then
	printf '\nobj-$(CONFIG_VIDEO_IMX519) += imx519.o\n' >> "$MK"
	echo "Added imx519.o to $MK"
fi

cp -v "$ROOT/dts/imx93-11x11-evk-imx519.dts" "$DTS/"
if [ -f "$DTS/imx93-11x11-frdm.dts" ]; then
	cp -v "$ROOT/dts/imx93-11x11-frdm-imx519.dts" "$DTS/"
else
	echo "Note: imx93-11x11-frdm.dts not in this tree; skipped FRDM DTB"
fi

if ! grep -q 'imx93-11x11-evk-imx519.dtb' "$DTMK"; then
	printf '\ndtb-$(CONFIG_ARCH_MXC) += imx93-11x11-evk-imx519.dtb\n' >> "$DTMK"
	if [ -f "$DTS/imx93-11x11-frdm.dts" ]; then
		printf 'dtb-$(CONFIG_ARCH_MXC) += imx93-11x11-frdm-imx519.dtb\n' >> "$DTMK"
	fi
	echo "Added IMX519 dtb targets to $DTMK"
fi

mkdir -p "$KSRC/arch/arm64/configs"
cp -v "$ROOT/configs/imx519.cfg" "$KSRC/arch/arm64/configs/imx519.config"

echo
echo "Installed into $KSRC"
echo "Next:"
echo "  cd $KSRC"
echo "  # enable CONFIG_VIDEO_IMX519=m and CONFIG_VIDEO_AK7375=m in your defconfig"
echo "  make imx_v8_defconfig"
echo "  ./scripts/kconfig/merge_config.sh -m .config arch/arm64/configs/imx519.config"
echo "  make olddefconfig"
echo "  make -j\$(nproc) Image dtbs modules"
echo "  # boot with fdtfile=imx93-11x11-evk-imx519.dtb"
