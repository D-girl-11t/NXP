# Troubleshooting IMX519 on i.MX93

## `insmod`: Invalid parameters / `modprobe`: Invalid argument

```
imx519: disagrees about version of symbol _dev_info
imx519: Unknown symbol _dev_info (err -22)
imx519: disagrees about version of symbol i2c_register_driver
```

`depmod -a` cannot fix this. The `.ko` was compiled against a **different
kernel ABI** than the `Image` that is running.

On FRDM this shows up as two different vermagic strings:

```
imx519.ko:   6.18.2-gf49f45233f7b-dirty SMP preempt mod_unload modversions aarch64
in-tree .ko: 6.18.2-1.0.0-gf49f45233f7b SMP preempt mod_unload modversions aarch64
```

`-dirty` means the laptop linux-imx tree had local edits. `-1.0.0` is
Yocto `CONFIG_LOCALVERSION`. With `CONFIG_MODVERSIONS=y` the loader then
rejects symbol CRCs (`disagrees about version of symbol`).

`ls /lib/modules/$(uname -r)/build` missing means this image has **no
kernel headers**. You cannot rebuild `imx519.ko` on the board. Keep the
IMX519 DTB; replace **`Image` and modules together**.

DTB can be correct at the same time (`2-001a` / `2-000c` in
`/sys/bus/i2c/devices/`).

### Fix — replace `Image` (no `/build` on the board)

**1. On the board** — export the running config and copy it off (zmodem,
USB, whatever you used for the DTB):

```bash
zcat /proc/config.gz > /tmp/running.config
ls -l /tmp/running.config
grep LOCALVERSION /tmp/running.config
# sz /tmp/running.config     # if you use lrzsz on serial
```

If `/proc/config.gz` is missing, this BSP was built without
`CONFIG_IKCONFIG_PROC`; you then need the `.config` from the Yocto build
that produced `gf49f45233f7b`.

**2. On the laptop** — same linux-imx tag as the board (`lf-6.18.2-1.0.0`):

```bash
cd ~/imx519-nxp-link
./scripts/install-into-kernel.sh ~/linux-imx
./scripts/rebuild-image-from-running-config.sh ~/linux-imx /path/to/running.config
```

(`imx_v8_defconfig` is the wrong starting point if you intend to keep the
stock Yocto `Image`.)

**3. On the board** — overwrite FAT `Image` the same way you overwrote
`imx93-11x11-frdm.dtb` (U-Boot already loads that filename):

```bash
ls /run/media/boot-mmcblk0p1/Image
cp /run/media/boot-mmcblk0p1/Image /run/media/boot-mmcblk0p1/Image.before-imx519
cp /path/to/new/Image /run/media/boot-mmcblk0p1/Image
sync
```

Install the new modules into the rootfs (`make INSTALL_MOD_PATH=...
modules_install` with the card mounted on the laptop, or copy
`drivers/media/i2c/imx519.ko` plus the rest of `/lib/modules/<new-uname>/`
if `uname -r` changes, e.g. gains `-dirty`). Reboot, then:

```bash
uname -r
modprobe imx519
dmesg | grep -i imx519 | tail -20
i2cdetect -y 2
```

Do not mix stock `Image` with a laptop-built `.ko`. A `-dirty` uname after
this reboot is fine as long as the `.ko` came from that same build.

### If `/lib/modules/$(uname -r)/build` exists (headers present)

Then you can rebuild only the module on the board:

```bash
cd /path/to/imx519-nxp-link
./scripts/build-module-on-target.sh
```

This FRDM demo image does not ship that directory.

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

First check the connector. On **FRDM-i.MX93 the camera goes in P6**, the
MIPI CSI FPC connector. P7 is MIPI DSI (display) and looks identical. P7
still supplies 3.3 V and I2C3, but pin 18 is `DSI_CTP_nINT` instead of
`CAM_MCLK` and pin 17 is `CTP_RST` instead of `CSI_nRST`, so the sensor has
no 24 MHz clock and is never released from reset. It cannot ACK. See
[hardware.md](hardware.md).

Then check the flex cable for tears — a broken I2C or MCLK trace looks the
same from software.

Otherwise: the IMX519 stays in reset (`reset-gpios` / XCLR) until the driver
probes. `2-001a` in `/sys/bus/i2c/devices/` only means the device-tree node
exists. Scan again **after** a matching `imx519.ko` loads. `UU` at 0x50/0x53
is unrelated (other drivers).

## `modprobe imx519` succeeds but nothing probes

`modprobe` exits 0, `lsmod` lists the module, and dmesg has no chip-id line
and no error. The module registered but the device never got a probe call.

```bash
lsmod | grep imx519
ls /sys/bus/i2c/drivers/imx519/          # 2-001a here = bound
mount -t debugfs none /sys/kernel/debug 2>/dev/null
cat /sys/kernel/debug/devices_deferred
```

On FRDM the usual answer is a deferred-probe chain:

```
regulator-vddo  platform: supplier 2-0034 not ready
2-001a  i2c: supplier regulator-vddo not ready
```

`2-0034` is `adp5585_isp`, an ADP5585 I/O expander that lives on **NXP's
AP1302 camera module**, gating `AVDD_2V8` / `VDDIO_1V8` / `DVDD`. With the
Arducam plugged in instead, that expander never ACKs, its regulators never
register, and anything using them waits forever.

The fix is in this repo's FRDM DTS: the IMX519 and AK7375 nodes declare their
own always-on `regulator-fixed` supplies (`reg_imx519_vana`, `_vdig`,
`_vddl`) instead of borrowing `reg_avdd_2v8` / `reg_vddio_1v8`. The Arducam
B0371 has onboard LDOs and only needs the 3.3 V that P6 pin 22 always
provides. Rebuild the dtb if your DTS still references the stock rails.

The four `regulator-*` entries stay in `devices_deferred` afterwards. That is
harmless — they belong to the camera module you are not using.

A camera in P7 instead of P6 also produces silence, because the driver can
bind and still read nothing without MCLK.

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
