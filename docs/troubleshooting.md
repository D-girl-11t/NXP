# Troubleshooting

Every symptom here is one that actually occurred during bring-up, with the
diagnosis that explained it.

Start here:

| Symptom | Section |
| --- | --- |
| `insmod` / `modprobe` rejects the module | [Module refuses to load](#module-refuses-to-load) |
| `modprobe` succeeds but dmesg is empty | [Loads but never probes](#modprobe-imx519-succeeds-but-nothing-probes) |
| `MEDIA_BUS_FMT_SENSOR_DATA undeclared` | [Build failures](#build-failures) |
| `Label or path isi_0 not found` | [Build failures](#build-failures) |
| Graph shows `ap1302`, not `imx519` | [Wrong device tree](#graph-shows-ap1302-instead-of-imx519) |
| `failed to read chip id` | [Sensor does not answer](#sensor-does-not-answer) |
| `/dev/video0` exists but streaming times out | [Stream timeout](#devvideo0-exists-but-the-stream-times-out) |
| Image is green or pink | [Wrong Bayer order](#image-is-green-pink-or-shifted) |
| Focus control does nothing | [Autofocus](#autofocus-does-nothing) |

## Module refuses to load

```
insmod: ERROR: could not insert module ...: Invalid parameters
modprobe: ERROR: could not insert 'imx519': Invalid argument

imx519: disagrees about version of symbol _dev_info
imx519: Unknown symbol i2c_register_driver (err -22)
```

The `.ko` was compiled against a **different kernel ABI** than the `Image`
that is running. `depmod -a` cannot fix it.

Prove it by comparing vermagic:

```bash
./scripts/check-ko-abi.sh
```

or by hand:

```bash
modinfo /lib/modules/$(uname -r)/extra/imx519.ko | grep vermagic
modinfo $(modprobe -c | grep -m1 ' kernel/drivers' >/dev/null; \
          find /lib/modules/$(uname -r)/kernel -name '*.ko*' | head -1) \
        | grep vermagic
```

On FRDM this produced two different strings:

```
imx519.ko:   6.18.2-gf49f45233f7b-dirty     SMP preempt mod_unload modversions aarch64
in-tree .ko: 6.18.2-1.0.0-gf49f45233f7b     SMP preempt mod_unload modversions aarch64
```

`-dirty` means the host's `linux-imx` tree had uncommitted edits.
`-1.0.0` is Yocto's `CONFIG_LOCALVERSION`. With `CONFIG_MODVERSIONS=y` the
loader compares a CRC for every exported symbol, and a different `.config`
changes those CRCs — so every symbol is rejected, not just one.

The device tree can be perfectly correct at the same time: `2-001a` and
`2-000c` will be present in `/sys/bus/i2c/devices/` even though no driver can
load.

### Fix

Check whether the board has kernel headers:

```bash
ls /lib/modules/$(uname -r)/build
```

**If it exists**, rebuild only the module, on the board:

```bash
./scripts/build-module-on-target.sh
```

**If it is missing** — which is the case on NXP's prebuilt demo images — you
cannot rebuild on the board. Replace `Image` **and** `/lib/modules`
together, either by building from the board's own `/proc/config.gz` or by
installing a full defconfig build. Both routes are in
[build-and-flash.md](build-and-flash.md#5-choose-a-kernel-config).

Never mix a stock `Image` with a host-built `.ko`. A `-dirty` suffix in
`uname -r` after the swap is fine, as long as the module came from that same
build.

## `modprobe imx519` succeeds but nothing probes

`modprobe` exits 0, `lsmod` lists the module, and dmesg has no chip-id line
**and no error at all**. The module registered, but the device never got a
probe call.

```bash
lsmod | grep imx519
ls /sys/bus/i2c/drivers/imx519/        # 2-001a here means bound
mount -t debugfs none /sys/kernel/debug 2>/dev/null
cat /sys/kernel/debug/devices_deferred
```

The answer is normally a deferred-probe chain:

```
regulator-vddo  platform: supplier 2-0034 not ready
2-001a          i2c: supplier regulator-vddo not ready
```

`2-0034` is an ADP5585 I/O expander that gates `AVDD_2V8`, `VDDIO_1V8` and
`DVDD`. It lives **on NXP's AP1302 camera module**, not on the board itself.
If a device tree borrows those rails while a different camera is attached,
the expander never ACKs, its regulators never register, and everything
downstream waits forever.

The device trees in this repository avoid it: the sensor and focus-coil nodes
declare their own always-on `regulator-fixed` supplies — `reg_imx519_vana`,
`reg_imx519_vdig`, `reg_imx519_vddl` — because the Arducam module has
onboard LDOs and only needs the 3.3 V the connector always provides.

If your device tree still references `reg_avdd_2v8` or `reg_vddio_1v8`,
rebuild the dtb. Confirm the new one is actually booted:

```bash
ls -d /proc/device-tree/regulator-imx519-*
```

All three must be present. One or none means the old dtb is still loading.

The stock `regulator-*` entries remain in `devices_deferred` afterwards.
That is harmless — they belong to a camera module that is not plugged in.

## Build failures

### `MEDIA_BUS_FMT_SENSOR_DATA undeclared`

The `imx519.c` in the kernel tree is the Raspberry Pi / Unicam version. That
format code was removed from the kernel before 6.18. Use the single-pad port
from this repository:

```bash
grep -c MEDIA_BUS_FMT_SENSOR_DATA kernel/imx519.c     # must print 0
./scripts/install-into-kernel.sh ~/linux-imx
```

The install script now checks for this and refuses to copy the old file, so
the usual cause is a stale checkout of this project. Re-clone it.

### `Label or path isi_0 not found`

An lf-6.6 device tree is being built against a 6.12-or-later kernel. The
graph node names changed: lf-6.6 uses `isi_0` and `cameradev`, newer BSPs use
`mipi_csi_in` / `mipi_csi_out` / `isi_in`.

The install script picks the matching EVK variant and drops dtb targets that
cannot build. If you hit this with an older copy, remove the unused target:

```bash
sed -i '/imx93-11x11-evk-imx519.dtb/d' \
    ~/linux-imx/arch/arm64/boot/dts/freescale/Makefile
```

FRDM does not need the EVK dtb at all.

### Duplicate dtb target

Running the install script twice against an old copy could append the same
`dtb-$(CONFIG_ARCH_MXC) += ...` line twice. Deduplicate:

```bash
MK=~/linux-imx/arch/arm64/boot/dts/freescale/Makefile
awk '!/imx93-11x11-frdm-imx519.dtb/ || !seen++' "$MK" > "$MK.tmp" && mv "$MK.tmp" "$MK"
```

## Graph shows `ap1302` instead of `imx519`

You booted the stock board device tree. Check what is actually loaded:

```bash
cat /proc/device-tree/model     # should mention Arducam IMX519
```

Set `fdtfile` at the U-Boot prompt, or overwrite the filename U-Boot already
loads. `setenv` typed inside Linux does nothing. See
[build-and-flash.md](build-and-flash.md#8-point-u-boot-at-the-new-device-tree).

## Sensor does not answer

```bash
dmesg | grep -iE 'imx519|i2c|csi|isi'
./scripts/i2c-probe.sh 2
```

| Message | Likely cause |
| --- | --- |
| `failed to read chip id ... error -5` | No I2C reply: XCLR still asserted, no 24 MHz master clock, wrong bus, or a cable/adapter fault |
| `chip id mismatch` | Not an IMX519, or bus noise |
| `xclk frequency not supported` | The clock node is not 24 MHz |
| `link-frequency property not found` | The device-tree endpoint has no `link-frequencies` |
| `only 2 data lanes` | `data-lanes` is not `<1 2>` on the sensor endpoint |

`-5` is `EIO`. By the time the driver reports it, every software layer has
already done its job: regulators enabled, clock running, reset released,
and a register read attempted. The remaining variables are the connector,
the adapter, and the flex cable.

Check that the module is on the CSI connector and not the DSI one — on
FRDM-i.MX93 the two 22-pin sockets look identical, and only the CSI socket
carries the master clock and camera reset. See
[hardware.md](hardware.md#connectors).

Note that `2-001a` appearing in `/sys/bus/i2c/devices/` only means the
device-tree node exists, not that the sensor replied. And `UU` at `0x50` or
`0x53` in `i2cdetect` output is unrelated — those are other board devices.

## `/dev/video0` exists but the stream times out

1. Confirm the links:
   `imx519 → mxc-mipi-csi2.0 → mxc_isi.0 → capture`, via
   `media-ctl -d /dev/media0 -p`.
2. Set the same format on **every** pad —
   [`scripts/setup-pipeline.sh`](../scripts/setup-pipeline.sh) does this.
3. Enable the internal colour bars:
   `v4l2-ctl -d $SUBDEV --set-ctrl=test_pattern=1`. If bars appear, CSI-2 and
   ISI are fine and the problem is lens, exposure or focus.
4. On lf-6.1 and lf-6.6, check `hs-clk-range` in the device tree. For a
   408 MHz link (816 Mbps/lane) it must be `0x19`. The stock AP1302 value
   `0x2b` is for 1300 Mbps and will not lock this sensor. Newer BSPs ignore
   the property and program the PHY from `V4L2_CID_LINK_FREQ`.

## Image is green, pink or shifted

The Bayer order does not match what the demosaic step assumed. HFLIP and
VFLIP rotate the Bayer phase. The default is RGGB (`RG10`); try `GB10`,
`BA10` or `BG10`, or clear the flips on the sensor subdev. Mapping table in
[driver.md](driver.md#formats).

## 16 MP or 4K capture fails

Expected. The i.MX93 ISI is limited to 2K horizontal. Use 1920×1080 or
1280×720 — see [hardware.md](hardware.md#supported-modes).

## Autofocus does nothing

Enable `CONFIG_VIDEO_AK7375=m` and make sure the `ak7375@c` node is in the
device tree and bound (`2-000c` under `/sys/bus/i2c/drivers/ak7375/`). Then
use [`scripts/focus.sh`](../scripts/focus.sh).

There is no closed-loop autofocus in the kernel — on a Raspberry Pi,
libcamera drives the contrast sweep. For an equivalent here, use
`userspace/imx519_capture.py --autofocus`.
