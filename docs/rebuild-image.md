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

Copy `/tmp/running.config` to the laptop, e.g. `~/running.config`.

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
