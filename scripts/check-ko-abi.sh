#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Run on the board. Explains why insmod/modprobe of imx519.ko returned
# "Invalid parameters" / "Invalid argument" (vermagic / MODVERSIONS CRC).
set -eu

KVER="$(uname -r)"
KO="${1:-/lib/modules/${KVER}/extra/imx519.ko}"

echo "Running kernel: ${KVER}"
echo "Module file:    ${KO}"
echo

if [ ! -f "$KO" ]; then
	echo "No file at ${KO}"
	echo "Search: find /lib/modules /home /run/media -name 'imx519.ko'"
	exit 1
fi

if ! command -v modinfo >/dev/null 2>&1; then
	echo "modinfo not found; install kmod."
	exit 1
fi

echo "=== imx519.ko ==="
modinfo "$KO" | grep -E 'filename|vermagic|srcversion|depends' || true
echo

INTREE="$(find "/lib/modules/${KVER}/kernel" -name '*.ko' -o -name '*.ko.xz' 2>/dev/null | head -n 1 || true)"
if [ -n "$INTREE" ]; then
	echo "=== in-tree sample (${INTREE}) ==="
	modinfo "$INTREE" | grep -E 'filename|vermagic|srcversion' || true
	echo
fi

echo "=== kernel headers (needed to rebuild ON this board) ==="
if [ -d "/lib/modules/${KVER}/build" ]; then
	echo "OK  /lib/modules/${KVER}/build"
	ls -l "/lib/modules/${KVER}/build/Module.symvers" 2>/dev/null || echo "    (no Module.symvers in build/)"
else
	echo "MISSING  /lib/modules/${KVER}/build"
	echo "    Install kernel-devsrc from the same BSP, or rebuild Image+modules on the laptop."
fi
if [ -f /proc/config.gz ]; then
	echo "OK  /proc/config.gz (running .config can be extracted)"
else
	echo "MISSING  /proc/config.gz (CONFIG_IKCONFIG_PROC=n)"
fi
echo

echo "If dmesg says 'disagrees about version of symbol', depmod cannot fix it."
echo "The .ko was compiled against a different .config / Module.symvers than"
echo "${KVER}. Rebuild with scripts/build-module-on-target.sh, or replace"
echo "FAT Image + /lib/modules with one matching build (see docs/troubleshooting.md)."
