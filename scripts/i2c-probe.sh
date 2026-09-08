#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Probe I2C for IMX519 (0x1a) and AK7375 VCM (0x0c) on the CSI bus.
# On i.MX93 EVK/FRDM the camera I2C is typically LPI2C3 -> /dev/i2c-2.

set -eu

BUS="${1:-2}"

if ! command -v i2cdetect >/dev/null 2>&1; then
	echo "Install i2c-tools (i2cdetect)." >&2
	exit 1
fi

echo "Scanning /dev/i2c-${BUS} (override with: $0 <bus>)"
echo "  IMX519 sensor expected at 0x1a"
echo "  AK7375 VCM     expected at 0x0c"
echo "  (Both often show -- until imx519.ko probes and releases XCLR.)"
echo

i2cdetect -y "$BUS"

echo
echo "Chip ID register 0x0016 should read 0x0519:"
if command -v i2cget >/dev/null 2>&1; then
	# 16-bit register address, big-endian. i2cget cannot do 16-bit addr
	# natively on all builds; use i2ctransfer when available.
	if command -v i2ctransfer >/dev/null 2>&1; then
		echo -n "  IMX519 0x0016 = "
		i2ctransfer -y "$BUS" w2@0x1a 0x00 0x16 r2 || echo "(no ACK — sensor not powered or wrong bus)"
	fi
fi
