#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Rebuild imx519.ko against the RUNNING kernel and load it.
# Must be run ON the board (native aarch64 gcc + kernel headers).
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/kernel"
KVER="$(uname -r)"
BUILD="/lib/modules/${KVER}/build"
DEST="/lib/modules/${KVER}/extra"

if [ ! -f "${SRC}/imx519.c" ] || [ ! -f "${SRC}/Makefile" ]; then
	echo "This script expects ${SRC}/imx519.c and Makefile." >&2
	exit 1
fi

if [ ! -d "$BUILD" ]; then
	echo "No kernel build tree at ${BUILD}" >&2
	echo >&2
	echo "This image did not ship kernel-devsrc. Pick one:" >&2
	echo "  1. dnf/rpm install kernel-devsrc (same BSP that produced ${KVER})" >&2
	echo "  2. On the laptop, rebuild Image + modules with the board's" >&2
	echo "     /proc/config.gz and copy BOTH onto the card — not only imx519.ko" >&2
	echo "  See docs/troubleshooting.md (section: disagrees about version of symbol)" >&2
	exit 1
fi

if ! command -v make >/dev/null 2>&1 || ! command -v gcc >/dev/null 2>&1; then
	echo "Need make + gcc on the board (package group 'tools' / build-essential)." >&2
	exit 1
fi

echo "Building against ${BUILD}"
make -C "$BUILD" M="$SRC" modules

mkdir -p "$DEST"
cp -v "${SRC}/imx519.ko" "${DEST}/imx519.ko"
depmod -a
modprobe -r imx519 2>/dev/null || true
modprobe imx519

echo
dmesg | grep -i imx519 | tail -n 25
echo
echo "Expect: 'Device found is imx519' (or similar probe success),"
echo "not 'disagrees about version of symbol'."
