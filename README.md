# Arducam IMX519 16 MP autofocus camera on NXP i.MX93

A Linux camera bring-up project: a V4L2 sensor driver, device trees, and
capture tooling that let a **Sony IMX519** 16 MP autofocus module work on an
**NXP i.MX93** board, which has no vendor support for this sensor.

It doubles as a worked example of Embedded Linux camera work — V4L2
sub-devices, the media controller graph, device-tree integration, kernel
module ABI, and Bayer capture without an ISP.

```
IMX519  ──2-lane CSI-2, RAW10──▶  i.MX93 DWC CSI-2  ──▶  ISI  ──▶  /dev/videoN
   sensor I2C 0x1a, focus coil 0x0c, both on LPI2C3 (= /dev/i2c-2)
```

| | |
| --- | --- |
| Camera | Arducam 16 MP autofocus (Sony IMX519 + AK7375 VCM), SKU B0371 |
| Boards | FRDM-i.MX93 and i.MX93 11x11 EVK |
| Kernel | NXP `linux-imx`, tested on 6.18.2; version-guarded for 6.1–6.18 |
| Output | Bayer RAW10 (`RG10`) at 1920×1080 or 1280×720 |

---

## 1. Goal

Capture stills and video from the Arducam 16 MP autofocus camera on an
i.MX93 board running NXP's `linux-imx` BSP, with working manual focus, using
only standard V4L2 userspace (`media-ctl`, `v4l2-ctl`).

## 2. Problem statement

Nothing about this camera works out of the box, for three independent
reasons.

**The board's device tree describes a different camera.** Both the FRDM and
the EVK BSP ship a device tree for NXP's **AP1302** ISP module on the CSI
connector. The IMX519 is not in it, so Linux never looks for the sensor and
no amount of userspace configuration helps.

**The only existing IMX519 driver is written for Raspberry Pi.** The driver
in the Raspberry Pi kernel (`drivers/media/i2c/imx519.c`) assumes the Pi's
Unicam receiver, the Pi hardware ISP, and libcamera. It exposes a second
"embedded data" metadata pad that only Unicam understands, and it defaults
to the sensor's full 4656×3496 mode.

**i.MX93 cannot run that pipeline.** It has a Synopsys DesignWare CSI-2
receiver feeding an ISI, **no hardware ISP at all**, and the ISI is limited
to roughly 2K horizontal and 200 Mpixel/s. So 16 MP cannot be captured, and
frames arrive as **Bayer RAW10** rather than YUV — colour has to be
reconstructed in software.

Full detail: [docs/hardware.md](docs/hardware.md).

## 3. What we did, step by step

### Step 1 — Port the sensor driver to i.MX93

Started from the Raspberry Pi `imx519.c` and adapted it for a plain CSI-2
host with no ISP ([`kernel/imx519.c`](kernel/imx519.c)):

- Removed the Unicam embedded-data metadata pad, leaving a single
  `IMAGE_PAD`. That also removed the dependency on
  `MEDIA_BUS_FMT_SENSOR_DATA`, which no longer exists in kernel 6.18.
- Moved to current V4L2 APIs (`v4l2_subdev_state_get_format`,
  `linux/unaligned.h`) behind `LINUX_VERSION_CODE` guards so the same file
  still builds on 6.1 through 6.18.
- Made **1920×1080** the default mode and added 1280×720, because the ISI
  cannot accept anything wider, and set the CSI-2 link frequency to
  **408 MHz** (816 Mbps/lane).
- Added a CSI-2 frame descriptor and mbus config so the DWC CSI-2 receiver
  and the i.MX93 ISI gasket can negotiate the link.

Design notes: [docs/driver.md](docs/driver.md).

### Step 2 — Write board device trees

[`dts/imx93-11x11-frdm-imx519.dts`](dts/imx93-11x11-frdm-imx519.dts) includes
the stock FRDM tree and then:

- deletes the AP1302 node,
- adds `imx519@1a` and `ak7375@c` on `lpi2c3`,
- wires the sensor endpoint into the 6.18 CSI graph via `mipi_csi_in`,
- declares the camera reset line, and
- gives the sensor its own always-on regulators (see step 6).

[`dts/imx93-11x11-evk-imx519.dts`](dts/imx93-11x11-evk-imx519.dts) does the
same for the 11x11 EVK, with an lf-6.6 variant for older BSPs.

### Step 3 — Make it build inside `linux-imx`

[`scripts/install-into-kernel.sh`](scripts/install-into-kernel.sh) copies the
driver, `Kconfig`, device trees, and config fragment into an NXP kernel tree
and patches the two `Makefile`s. It also refuses to run against a stale copy
of the project, which is how the early build failures happened.

### Step 4 — Match the kernel module ABI

The first attempts to load the module failed outright. Diagnosing this was
the single largest piece of work in the project; see
[problem 1](#problem-1-the-module-refuses-to-load) below. The resolution was
to build and install a matching `Image` **and** `/lib/modules` together,
keeping the stock kernel on the boot partition as a rescue image.

### Step 5 — Get files onto the board

A direct Ethernet cable between laptop and board has no DHCP server, so
`udhcpc` never gets a lease. Static addressing on both ends makes `scp`
work; see [docs/build-and-flash.md](docs/build-and-flash.md).

### Step 6 — Give the camera its own power supplies

With a matching kernel, `modprobe imx519` returned success and printed
nothing at all — the module registered but the device never got a probe
call. The cause was a deferred-probe chain; see
[problem 2](#problem-2-the-driver-loads-but-never-probes). The fix was to
stop borrowing the stock board's camera rails and declare always-on fixed
regulators in the device tree instead.

### Step 7 — Verify the driver binds and probes

With the matching kernel and the corrected device tree:

```
# uname -r
6.18.2-gf49f45233f7b-dirty
# cat /proc/device-tree/model
NXP FRDM-i.MX93 with Arducam IMX519
# modprobe imx519                     # loads with no symbol errors
# ls /sys/bus/i2c/drivers/imx519/     # 2-001a appears once bound
```

The AK7375 focus coil binds at `2-000c`, nothing sits in deferred probe, and
the driver runs its full probe sequence: enable regulators, start the 24 MHz
clock, release reset, then read the chip id over I2C.

### Step 8 — Capture tooling

Shell helpers wire the media graph and pull frames
([`scripts/`](scripts/)), and Python tools demosaic the Bayer data into PNG
or JPEG ([`userspace/`](userspace/)), since there is no ISP to do it in
hardware. Details in [docs/capture.md](docs/capture.md).

## 4. Problems encountered, and how they were fixed

| Problem | Root cause | Fix |
| --- | --- | --- |
| `modprobe`: `Invalid argument`, `disagrees about version of symbol` | Module built against a different kernel ABI | Rebuild and install `Image` + modules together |
| `modprobe` succeeds, no probe, no dmesg | Deferred probe behind an I2C expander on the absent AP1302 module | Own always-on regulators in the DTS |
| `MEDIA_BUS_FMT_SENSOR_DATA undeclared` | Raspberry Pi driver still in the tree | Use the single-pad port; the install script now rejects the old file |
| `Label or path isi_0 not found` | lf-6.6 EVK device tree built against a 6.18 kernel | Install script picks the matching variant and drops unused dtb targets |
| `udhcpc` never gets a lease | Direct laptop-to-board cable, no DHCP server | Static IPs on both ends |
| Graph still shows `ap1302` | U-Boot loaded the stock dtb | Set `fdtfile`, or overwrite the filename U-Boot already loads |

### Problem 1: the module refuses to load

```
insmod: ERROR: could not insert module ...: Invalid parameters
modprobe: ERROR: could not insert 'imx519': Invalid argument

imx519: disagrees about version of symbol _dev_info
imx519: Unknown symbol i2c_register_driver (err -22)
```

`depmod -a` cannot fix this. Comparing `modinfo` output showed two different
vermagic strings:

| | vermagic |
| --- | --- |
| our `imx519.ko` | `6.18.2-gf49f45233f7b-dirty` |
| running kernel | `6.18.2-1.0.0-gf49f45233f7b` |

`-dirty` comes from local edits in the laptop kernel tree; `-1.0.0` is
Yocto's `CONFIG_LOCALVERSION`. With `CONFIG_MODVERSIONS=y`, the module loader
compares a CRC for every exported symbol, and a different `.config` produces
different CRCs — so every symbol is rejected.

`/lib/modules/$(uname -r)/build` did not exist, meaning the BSP image ships
**no kernel headers**, so the module could not be rebuilt on the board. The
only remaining option was to replace the kernel and its modules together.
[`scripts/check-ko-abi.sh`](scripts/check-ko-abi.sh) reports this mismatch
directly.

### Problem 2: the driver loads but never probes

`modprobe` exited 0, `lsmod` listed the module, and dmesg had no chip-id line
and no error. `/sys/bus/i2c/drivers/imx519/` was empty, so the device had
never been handed to the driver.

```bash
mount -t debugfs none /sys/kernel/debug
cat /sys/kernel/debug/devices_deferred
```

```
regulator-vddo  platform: supplier 2-0034 not ready
2-001a          i2c: supplier regulator-vddo not ready
```

`2-0034` is an ADP5585 I/O expander that gates `AVDD_2V8`, `VDDIO_1V8` and
`DVDD` — and it lives **on NXP's AP1302 camera module**, not on the board.
Our device tree had borrowed those rails from the stock tree, so with a
different camera attached the expander never ACKed, its regulators never
registered, and the sensor waited behind them forever.

The Arducam module carries its own LDOs and only needs the 3.3 V the
connector supplies unconditionally, so the device tree now declares
`reg_imx519_vana`, `reg_imx519_vdig` and `reg_imx519_vddl` as always-on fixed
regulators. The stock `regulator-*` entries remain in `devices_deferred`
afterwards, which is harmless — they belong to a camera module that is not
present.

More symptoms and checks: [docs/troubleshooting.md](docs/troubleshooting.md).

## 5. How to use this code

### Prerequisites

On a Linux host (or WSL2 — see [docs/windows.md](docs/windows.md)):

```bash
sudo apt install -y git build-essential gcc-aarch64-linux-gnu \
    bc bison flex libssl-dev device-tree-compiler
```

Clone NXP's kernel at the **same tag as your board**. Check with `uname -r`
on the board first:

```bash
git clone -b lf-6.18.2-1.0.0 https://github.com/nxp-imx/linux-imx.git ~/linux-imx
```

On the board you need `v4l-utils` (`media-ctl`, `v4l2-ctl`) and `i2c-tools`.

### Build

```bash
./scripts/install-into-kernel.sh ~/linux-imx

cd ~/linux-imx
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make imx_v8_defconfig
./scripts/kconfig/merge_config.sh -m .config arch/arm64/configs/imx519.config
make olddefconfig
make -j"$(nproc)" Image modules dtbs
```

> If you intend to keep the stock BSP `Image` on the board, do **not** start
> from `imx_v8_defconfig` — the resulting module will not load. Start from
> the board's own `/proc/config.gz` instead, or plan to replace `Image` and
> `/lib/modules` together. Both routes are in
> [docs/build-and-flash.md](docs/build-and-flash.md).

Outputs:

```
arch/arm64/boot/Image
arch/arm64/boot/dts/freescale/imx93-11x11-frdm-imx519.dtb
drivers/media/i2c/imx519.ko
```

### Install and boot

Copy `Image` to the boot partition, the dtb next to the stock one, and the
modules into the rootfs. Then tell U-Boot which device tree to load:

```
setenv fdtfile imx93-11x11-frdm-imx519.dtb
saveenv
boot
```

Use `imx93-11x11-evk-imx519.dtb` on the EVK. Keep a copy of the original
`Image` on the boot partition — if a new kernel does not boot, U-Boot can
only load a rescue image from there.

Step-by-step, including SD-card and `scp` routes:
[docs/build-and-flash.md](docs/build-and-flash.md).

### Capture

```bash
./scripts/i2c-probe.sh 2                  # sensor 0x1a, focus coil 0x0c
modprobe imx519
./scripts/setup-pipeline.sh 1920 1080     # wire the media graph, RAW10
./scripts/capture-still.sh shot.raw
./scripts/capture-video.sh 60 clip.raw    # 60 RAW frames
./scripts/focus.sh 512                    # AK7375 focus DAC
```

Then demosaic on the host or the board:

```bash
pip install -r userspace/requirements.txt
python3 userspace/raw10_to_png.py --width 1920 --height 1080 shot.raw shot.png
```

`/dev/video0` is Bayer RAW, not a YUV webcam — there is no ISP. Colour comes
from the demosaic step. Formats, controls and test patterns:
[docs/capture.md](docs/capture.md).

### Yocto

For a BSP build rather than a manual kernel build, the layer in
[`yocto/meta-imx519`](yocto/meta-imx519) carries the driver, device trees and
tools as recipes. See [docs/yocto.md](docs/yocto.md).

## 6. Repository layout

```
kernel/imx519.c         V4L2 sub-device driver for the sensor (GPL-2.0)
kernel/Kconfig          CONFIG_VIDEO_IMX519
kernel/Makefile         out-of-tree module build
configs/imx519.cfg      kernel config fragment for merge_config.sh
dts/                    FRDM and EVK device trees (+ lf-6.6 EVK variant)
scripts/                install, ABI check, pipeline, capture, focus
userspace/              Python demosaic and capture tools
yocto/meta-imx519/      optional Yocto layer
docs/                   hardware, driver, build, capture, troubleshooting
```

## 7. Documentation

| Document | Covers |
| --- | --- |
| [docs/hardware.md](docs/hardware.md) | i.MX93 camera block, ISI limits, supported modes, connectors, BSP differences |
| [docs/driver.md](docs/driver.md) | What the port changes versus the Raspberry Pi driver, controls, device-tree binding |
| [docs/build-and-flash.md](docs/build-and-flash.md) | Full laptop-and-board walkthrough, kernel ABI matching, getting files across |
| [docs/capture.md](docs/capture.md) | Media graph, stills, video, focus, demosaic, formats |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Symptom-to-cause table for every failure we hit |
| [docs/yocto.md](docs/yocto.md) | Building the layer into a BSP image |
| [docs/windows.md](docs/windows.md) | Doing the host side from Windows with WSL2 |
| [docs/resources.md](docs/resources.md) | Datasheets, application notes, upstream sources |
| [docs/bindings/sony,imx519.yaml](docs/bindings/sony,imx519.yaml) | Device-tree binding schema |

## 8. Resources

The primary references, with the full annotated list in
[docs/resources.md](docs/resources.md):

- [NXP `linux-imx` kernel](https://github.com/nxp-imx/linux-imx) — the BSP
  kernel the board actually boots.
- [i.MX 93 Applications Processor Reference Manual (IMX93RM)](https://www.nxp.com/docs/en/reference-manual/IMX93RM.pdf)
  — MIPI CSI-2 receiver and ISI chapters.
- [FRDM-IMX93 Board User Manual (UM12181)](https://www.nxp.com/webapp/Download?colCode=UM12181)
  — connector pinouts and board power rails.
- [Raspberry Pi `imx519.c`](https://github.com/raspberrypi/linux/blob/rpi-6.6.y/drivers/media/i2c/imx519.c)
  — the driver this port started from.
- [Arducam 16 MP IMX519 documentation](https://docs.arducam.com/Raspberry-Pi-Camera/Native-camera/16MP-IMX519/)
  — module-level wiring and sensor modes.
- [Linux kernel camera sensor driver guidelines](https://docs.kernel.org/driver-api/media/camera-sensor.html)
  — the conventions this driver follows.
- [V4L2 sub-device and media controller API](https://docs.kernel.org/userspace-api/media/v4l/dev-subdev.html)
  — what `media-ctl` and `v4l2-ctl` are driving.

## License and credits

The driver is **GPL-2.0**, as required for a Linux kernel module. Sensor
register tables and the original V4L2 driver are
Copyright (C) 2021 Arducam Technology co., Ltd., based on the Sony IMX477
driver, Copyright (C) 2020 Raspberry Pi (Trading) Ltd. Device trees and
scripts in this repository are also GPL-2.0; see [LICENSE](LICENSE).
