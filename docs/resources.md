# Resources

Everything this port was built from, grouped by what you would reach for it.

## NXP i.MX93 silicon and BSP

| Resource | Why |
| --- | --- |
| [`nxp-imx/linux-imx`](https://github.com/nxp-imx/linux-imx) | The BSP kernel the board boots. Clone the tag matching `uname -r` — `lf-6.18.2-1.0.0` for this project. |
| [i.MX 93 Applications Processor Reference Manual (IMX93RM)](https://www.nxp.com/docs/en/reference-manual/IMX93RM.pdf) | The MIPI CSI-2 receiver, ISI and ISI gasket chapters, plus the LPI2C and CCM clock-output registers. Requires an NXP account. |
| [i.MX 93 Applications Processor Datasheet (IMX93CEC)](https://www.nxp.com/docs/en/data-sheet/IMX93CEC.pdf) | Electrical limits, including the CSI-2 D-PHY per-lane rate. |
| [i.MX Linux Release Notes and User's Guide](https://www.nxp.com/design/design-center/software/embedded-software/i-mx-software/embedded-linux-for-i-mx-applications-processors:IMXLINUX) | Which kernel version ships in which BSP release, and the Yocto manifest tags. |
| [i.MX Yocto Project User's Guide](https://www.nxp.com/docs/en/user-guide/IMX_YOCTO_PROJECT_USERS_GUIDE.pdf) | Needed only for the [Yocto route](yocto.md). |
| [AN14012 — i.MX 93 to i.MX 91 Design Compatibility Guide](https://www.nxp.com/docs/en/application-note/AN14012.pdf) | §3.2 is the authority on i.MX91 having no MIPI CSI-2. |

## Boards

| Resource | Why |
| --- | --- |
| [FRDM-IMX93 product page](https://www.nxp.com/design/design-center/development-boards-and-designs/FRDM-IMX93) | Design files (schematic, BOM, Gerbers) and the quick-start guide. |
| [UM12181 — FRDM-IMX93 Board User Manual](https://www.nxp.com/webapp/Download?colCode=UM12181) | Connector pinouts (tables 20 and 21), board power rails, and the I/O expander map. Note that §3.3.1 of Rev 2.0 names P7 for the camera while §2.14 and the pinout tables make P6 the only possibility; the tables are correct. |
| [MCIMX93-EVK Board User Manual](https://www.nxp.com/docs/en/user-manual/IMX93EVKHUG.pdf) | The 11x11 EVK's CSI connector (J801) and the AR0144 module it ships with. |
| [i.MX 93 EVK product page](https://www.nxp.com/design/design-center/development-boards-and-designs/MCIMX93-EVK) | Board design files. |

## Camera module

| Resource | Why |
| --- | --- |
| [Arducam 16 MP IMX519 documentation](https://docs.arducam.com/Raspberry-Pi-Camera/Native-camera/16MP-IMX519/) | Module wiring, sensor modes, I2C addresses, and the autofocus coil. |
| [Arducam `imx519` kernel sources](https://github.com/ArduCAM/Arducam-Pivariety-V4L2-Driver) | Arducam's own packaging of the driver and overlays. |
| Sony IMX519 datasheet | Register-level detail. Available from Sony under NDA only; the register tables in `kernel/imx519.c` are the practical substitute. |
| [AK7375 datasheet (Asahi Kasei)](https://www.akm.com/content/dam/documents/products/driver/motor-driver-lens-actuator/ak7375/ak7375-en-datasheet.pdf) | The voice-coil focus driver at I2C `0x0c`. |
| [MIPI CSI-2 specification](https://www.mipi.org/specifications/csi-2) | Data types (RAW10 is `0x2b`), virtual channels, and D-PHY timing. Membership required for the full text. |

## Upstream Linux

| Resource | Why |
| --- | --- |
| [Raspberry Pi `imx519.c`](https://github.com/raspberrypi/linux/blob/rpi-6.6.y/drivers/media/i2c/imx519.c) | The driver this port started from. Compare against `kernel/imx519.c` to see the changes described in [driver.md](driver.md). |
| [Camera sensor driver guidelines](https://docs.kernel.org/driver-api/media/camera-sensor.html) | The conventions a V4L2 sensor driver is expected to follow — control semantics, power management, format negotiation. |
| [V4L2 sub-device API](https://docs.kernel.org/userspace-api/media/v4l/dev-subdev.html) | What `media-ctl --set-v4l2` is really doing. |
| [Media controller API](https://docs.kernel.org/userspace-api/media/mediactl/media-controller.html) | Entities, pads and links — the model behind the pipeline diagram. |
| [V4L2 control IDs](https://docs.kernel.org/userspace-api/media/v4l/control.html) | Reference for the controls listed in [driver.md](driver.md#controls). |
| [`Documentation/devicetree/bindings/media/i2c/`](https://github.com/torvalds/linux/tree/master/Documentation/devicetree/bindings/media/i2c) | Binding conventions; `sony,imx519.yaml` here follows them. |
| [`Documentation/devicetree/bindings/media/video-interfaces.yaml`](https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/media/video-interfaces.yaml) | The `data-lanes`, `link-frequencies` and `clock-noncontinuous` endpoint properties. |
| [`drivers/media/platform/nxp/imx8-isi/`](https://github.com/torvalds/linux/tree/master/drivers/media/platform/nxp/imx8-isi) | The ISI driver, shared across i.MX8 and i.MX9. Read `imx8-isi-core.c` for the per-SoC capability tables. |
| [`drivers/media/platform/nxp/dwc-mipi-csi2.c`](https://github.com/torvalds/linux/blob/master/drivers/media/platform/nxp/dwc-mipi-csi2.c) | The CSI-2 receiver on 6.12 and later. On lf-6.1 and lf-6.6 the same driver lives under `drivers/staging/media/imx/`. |
| [linux-media mailing list](https://lore.kernel.org/linux-media/) | Where the i.MX9 ISI and CSI-2 patches were reviewed, including the i.MX91 parallel-only series. |

## Tooling

| Resource | Why |
| --- | --- |
| [`v4l-utils`](https://git.linuxtv.org/v4l-utils.git/) | `media-ctl`, `v4l2-ctl`, `v4l2-compliance`. |
| [`v4l2-ctl` reference](https://www.mankier.com/1/v4l2-ctl) | Flag reference for the capture scripts. |
| [`media-ctl` reference](https://www.mankier.com/1/media-ctl) | Pad format syntax used by `setup-pipeline.sh`. |
| [Kernel module versioning (`modversions`)](https://docs.kernel.org/kbuild/modules.html) | Why a mismatched `.ko` produces `disagrees about version of symbol`. |
| [Kbuild external module documentation](https://docs.kernel.org/kbuild/modules.html#building-external-modules) | The out-of-tree build in `kernel/Makefile`. |
| [Deferred probe and `fw_devlink`](https://docs.kernel.org/driver-api/driver-model/driver.html) | Background for `/sys/kernel/debug/devices_deferred`. |

## Background reading

- [Introduction to the V4L2 framework](https://docs.kernel.org/driver-api/media/v4l2-intro.html)
  — the architecture this driver plugs into.
- [libcamera](https://libcamera.org/) — what fills the 3A and autofocus gap
  on platforms that have an ISP, and the reason the Raspberry Pi driver looks
  the way it does.
- [Bayer filter and demosaicing](https://en.wikipedia.org/wiki/Demosaicing) —
  what `userspace/raw10_to_png.py` implements.
