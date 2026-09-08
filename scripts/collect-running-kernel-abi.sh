#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Run ON the board. Packs the running kernel ABI so a laptop can rebuild
# a matching Image + imx519.ko (or confirm headers are missing).
set -eu

KVER="$(uname -r)"
OUT="${1:-/tmp/kernel-abi-${KVER}}"

rm -rf "$OUT"
mkdir -p "$OUT"

uname -a > "${OUT}/uname.txt"
echo "$KVER" > "${OUT}/uname-r.txt"

if [ -f /proc/config.gz ]; then
	zcat /proc/config.gz > "${OUT}/config"
	echo "Wrote ${OUT}/config from /proc/config.gz"
else
	echo "No /proc/config.gz" > "${OUT}/config.MISSING"
fi

if [ -f "/lib/modules/${KVER}/build/Module.symvers" ]; then
	cp "/lib/modules/${KVER}/build/Module.symvers" "${OUT}/Module.symvers"
	echo "Wrote ${OUT}/Module.symvers"
else
	echo "No Module.symvers under /lib/modules/${KVER}/build" > "${OUT}/Module.symvers.MISSING"
fi

if [ -d "/lib/modules/${KVER}/build" ]; then
	ls -la "/lib/modules/${KVER}/build" > "${OUT}/build-dir.txt" 2>&1 || true
	readlink -f "/lib/modules/${KVER}/build" > "${OUT}/build-realpath.txt" 2>/dev/null || true
else
	echo "MISSING" > "${OUT}/build-dir.txt"
fi

if command -v modinfo >/dev/null 2>&1; then
	KO="$(find "/lib/modules/${KVER}/kernel" \( -name '*.ko' -o -name '*.ko.xz' \) 2>/dev/null | head -n 1 || true)"
	if [ -n "$KO" ]; then
		modinfo "$KO" > "${OUT}/intree-modinfo.txt" || true
	fi
	if [ -f "/lib/modules/${KVER}/extra/imx519.ko" ]; then
		modinfo "/lib/modules/${KVER}/extra/imx519.ko" > "${OUT}/imx519-modinfo.txt" || true
	fi
fi

TAR="/tmp/kernel-abi-${KVER}.tar.gz"
tar -C "$(dirname "$OUT")" -czf "$TAR" "$(basename "$OUT")"
echo
echo "Packed ${TAR}"
echo "Copy that file to the laptop (sz / scp / USB) if you rebuild Image there."
