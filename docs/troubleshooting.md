# Troubleshooting IMX519 on i.MX93

## `insmod`: Invalid parameters / `modprobe`: Invalid argument

```
imx519: disagrees about version of symbol _dev_info
imx519: Unknown symbol _dev_info (err -22)
imx519: disagrees about version of symbol i2c_register_driver
```

`depmod -a` cannot fix this. The `.ko` on the board was compiled against a
**different kernel ABI** than `uname -r` (different `.config` and
`Module.symvers` CRCs). Typical cause: laptop `make imx_v8_defconfig` while
the FRDM still runs the **Yocto** kernel `6.18.2-1.0.0-gf49f45233f7b`.

DTB can be correct at the same time. `ls /sys/bus/i2c/devices/` showing
`2-001a` and `2-000c` means the overlay is live; only the module is wrong.

On the board:

```bash
# confirm mismatch (vermagic / srcversion vs any in-tree .ko)
/path/to/imx519-nxp-link/scripts/check-ko-abi.sh

modinfo /lib/modules/$(uname -r)/extra/imx519.ko | grep vermagic
modinfo $(find /lib/modules/$(uname -r)/kernel -name '*.ko' | head -1) | grep vermagic
```

### Fix A — rebuild the module on the board (best if headers exist)

```bash
ls /lib/modules/$(uname -r)/build
# if that directory exists:
cd /path/to/imx519-nxp-link
./scripts/build-module-on-target.sh
```

Needs `gcc`, `make`, and `kernel-devsrc` (or an equivalent
`/lib/modules/$(uname -r)/build` with `Module.symvers`). Then:

```bash
dmesg | grep -i imx519 | tail -20
# success looks like chip-id / "imx519 2-001a"
i2cdetect -y 2
# 1a and 0c may only ACK after probe releases XCLR (reset GPIO)
```

### Fix B — replace `Image` and modules together (no headers on the board)

A new `imx519.ko` from `imx_v8_defconfig` will never load into the stock
Yocto `Image`. Copy **both**:

1. Extract the running config: `zcat /proc/config.gz > running.config`
   (or `./scripts/collect-running-kernel-abi.sh` and copy the tarball off).
2. On the laptop, in the linux-imx tree that matches the BSP tag
   (`lf-6.18.2-1.0.0`, commit `f49f45233f7b` if that is in `uname -r`):

```bash
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
cp running.config .config
# merge CONFIG_VIDEO_IMX519=m CONFIG_VIDEO_AK7375=m
./scripts/kconfig/merge_config.sh -m .config /path/to/imx519-nxp-link/configs/imx519.cfg
make olddefconfig
make -j"$(nproc)" Image modules dtbs
```

3. On the FAT boot partition, replace `Image` the same way you overwrote
   `imx93-11x11-frdm.dtb`. Install modules into the rootfs
   `/lib/modules/<new-uname>/`. Reboot, then `modprobe imx519`.

Do not mix stock `Image` with a laptop-built `.ko`.

## Sensor does not probe

```
dmesg | grep -iE 'imx519|i2c|csi|isi'
i2c-probe.sh 2
```

| Symptom | Likely cause |
| --- | --- |
| `failed to read chip id` | XCLR still low, 24 MHz not present, wrong I2C bus |
| `chip id mismatch` | not an IMX519 (or bus noise) |
| `xclk frequency not supported` | dummy clock is not 24 MHz |
| `link-frequency property not found` | DT endpoint missing `link-frequencies` |
| `only 2 data lanes` | DT `data-lanes` is not `<1 2>` on the sensor |

## `i2cdetect` shows `--` at 0x1a / 0x0c

The IMX519 stays in reset (`reset-gpios` / XCLR) until the driver probes.
`2-001a` in `/sys/bus/i2c/devices/` only means the device-tree node exists.
Scan again **after** a matching `imx519.ko` loads. `UU` at 0x50/0x53 is
unrelated (other drivers).

## Graph has AP1302 instead of IMX519

You booted the stock board DTB. On FRDM the working workaround is to
overwrite the FAT file U-Boot already loads (`imx93-11x11-frdm.dtb`) with
the IMX519 blob. `setenv` inside Linux does nothing; use U-Boot or
`fw_setenv` if that tool exists.

## `/dev/video0` exists but stream times out

1. Confirm the media graph links:
   `imx519 -> mxc-mipi-csi2.0 -> mxc_isi.0 -> capture`.
2. Set the same format on every pad (`scripts/setup-pipeline.sh`).
3. Enable colour bars: `v4l2-ctl -d $SUBDEV --set-ctrl=test_pattern=1`
   If bars appear, CSI/ISI are fine and the problem is lens/exposure/AF.
4. Check `hs-clk-range`. For 408 MHz link / 816 Mbps use `0x19` on lf-6.6.
   The stock AP1302 value `0x2b` (1300 Mbps) will not lock this sensor.

## Image is green/pink/shifted

Bayer order changed with HFLIP/VFLIP. Default is RGGB (`RG10`). Try
`GB10` / `BA10` / `BG10`, or unset flips on the sensor subdev.

## 16 MP / 4K requested and capture fails

i.MX93 ISI is 2K horizontal. Use 1920×1080 or 1280×720.

## Autofocus does nothing

Enable `CONFIG_VIDEO_AK7375=m` and the `ak7375@c` node. Then
`scripts/focus.sh 512`. There is no closed-loop AF daemon on i.MX93;
libcamera on Pi is what usually drives contrast AF.
