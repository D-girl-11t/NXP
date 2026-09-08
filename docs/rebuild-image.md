# Rebuild Image from the board’s running config

Your laptop copy of this project may not have
`scripts/rebuild-image-from-running-config.sh` yet. You do not need it.
Run the same steps by hand.

`/path/to/running.config` in earlier notes was a **placeholder**. Use the
real file you copied off the board.

## 1. On the board

```bash
zcat /proc/config.gz > /tmp/running.config
ls -l /tmp/running.config
```

Copy `/tmp/running.config` to the laptop as **`~/running.config`**.
`ls ~/running.config` must succeed before `cp`. If that file is missing,
`merge_config.sh` keeps whatever `.config` was already in linux-imx
(`imx_v8_defconfig`, `CONFIG_LOCALVERSION=""`). That still builds, but you
**must replace FAT `Image` and modules** — the `.ko` will not load into the
stock Yocto kernel.

## Stale `~/imx519-nxp-link` (this is the usual failure)

An old tarball still has the Raspberry Pi driver (`MEDIA_BUS_FMT_SENSOR_DATA`)
and the lf-6.6 EVK DTS (`isi_0` / `cameradev`). That is exactly:

```
MEDIA_BUS_FMT_SENSOR_DATA undeclared
Label or path isi_0 not found
```

On FRDM you do not need the EVK DTB. In linux-imx:

```bash
grep MEDIA_BUS_FMT_SENSOR_DATA ~/imx519-nxp-link/kernel/imx519.c && echo STALE_DRIVER
sed -i '/imx93-11x11-evk-imx519.dtb/d' ~/linux-imx/arch/arm64/boot/dts/freescale/Makefile
```

Replace `~/imx519-nxp-link/kernel/imx519.c` with the current
`kernel/imx519.c` from this project (2259 lines, **no** `SENSOR_DATA`,
comment `single image stream`). Then:

```bash
cp ~/imx519-nxp-link/kernel/imx519.c ~/linux-imx/drivers/media/i2c/imx519.c
cd ~/linux-imx
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make -j"$(nproc)" Image modules dtbs
```

## 2. On the laptop (driver already installed into linux-imx)

```bash
ls ~/running.config          # must exist; do not type /path/to/...
test -f ~/linux-imx/drivers/media/i2c/imx519.c

cd ~/linux-imx
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

cp ~/running.config .config
./scripts/kconfig/merge_config.sh -m .config arch/arm64/configs/imx519.config
make olddefconfig
grep -E 'VIDEO_IMX519|VIDEO_AK7375|LOCALVERSION' .config

make -j"$(nproc)" Image modules dtbs
```

Outputs:

- `~/linux-imx/arch/arm64/boot/Image`
- `~/linux-imx/arch/arm64/boot/dts/freescale/imx93-11x11-frdm-imx519.dtb`
- `~/linux-imx/drivers/media/i2c/imx519.ko`

## 3. On the board — overwrite FAT `Image`

Same trick as the DTB. Backup first:

```bash
cp /run/media/boot-mmcblk0p1/Image /run/media/boot-mmcblk0p1/Image.before-imx519
cp /path/you/copied/Image /run/media/boot-mmcblk0p1/Image
sync
```

Install the matching modules into the rootfs, reboot, then `modprobe imx519`.
