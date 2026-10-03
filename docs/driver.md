# The IMX519 driver port

[`kernel/imx519.c`](../kernel/imx519.c) is a V4L2 **sub-device** driver. It
programs the Sony sensor over I2C and nothing else — it does not move pixels.
The CSI-2 receiver and ISI drivers already in `linux-imx` do that, and
userspace ties the three together through the media controller.

It started as the Raspberry Pi driver and was reworked for a CSI-2 host with
no ISP. This document records what changed and why, so the diff against
upstream is intelligible.

## Changes from the Raspberry Pi driver

### One pad instead of two

The Pi driver declares two source pads: an image pad and a second
`METADATA_PAD` that carries the sensor's embedded-data lines, typed
`MEDIA_BUS_FMT_SENSOR_DATA`. Only Unicam consumes that pad, and the format
code itself was removed from the kernel before 6.18, so the file no longer
compiles there.

```c
/* i.MX93 CSI/ISI is a single image stream (no Unicam embedded-data pad). */
enum pad_types {
	IMAGE_PAD,
	NUM_PADS
};
```

Dropping the pad removes the compile dependency and leaves a graph the ISI
can actually link to. A stale copy of the Pi driver is the usual cause of
`MEDIA_BUS_FMT_SENSOR_DATA undeclared`, so
[`scripts/install-into-kernel.sh`](../scripts/install-into-kernel.sh) checks
for it and refuses to install.

### Modes clamped to what the ISI can take

The sensor's register tables still describe all five modes, including full
16 MP, but a module parameter hides anything the ISI would reject:

```c
static unsigned int max_width = 2048;
module_param(max_width, uint, 0644);
MODULE_PARM_DESC(max_width,
		 "Hide Bayer modes wider than this (i.MX93 ISI max is 2048)");
```

`imx519_mode_allowed()` filters on it, so `VIDIOC_ENUM_FRAMESIZES` only
advertises 1920×1080 and 1280×720, and `imx519_default_mode()` returns the
first surviving entry — 1080p instead of the Pi's 4656×3496. Raising the
parameter re-exposes the wide modes for experimentation; see
[hardware.md](hardware.md#supported-modes).

### A 408 MHz link

```c
#define IMX519_DEFAULT_LINK_FREQ	408000000
```

816 Mbps per lane DDR, inside both the D-PHY ceiling and the ISI pixel-rate
budget. The device-tree endpoint must advertise the same value in
`link-frequencies`, and the driver rejects anything else — a mismatch is
reported as `link-frequency property not found` or a frequency error at
probe.

### CSI-2 frame descriptor and mbus config

The DWC CSI-2 receiver and the i.MX93 ISI gasket ask the sensor for its
CSI-2 data type and virtual channel before they will configure themselves.
The port implements `get_frame_desc` and `get_mbus_config` for that,
declaring RAW10 (data type `0x2b`) on virtual channel 0.

### Current V4L2 APIs, with version guards

`v4l2_subdev_get_try_format()` was replaced by
`v4l2_subdev_state_get_format()` (which takes no subdev argument) around 6.8
and is gone in 6.18. Rather than fork the file per BSP, both spellings sit
behind one macro:

```c
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 8, 0)
#define imx519_state_format(_sd, _state, _pad) \
	v4l2_subdev_state_get_format((_state), (_pad))
#else
#define imx519_state_format(_sd, _state, _pad) \
	v4l2_subdev_get_try_format((_sd), (_state), (_pad))
#endif
```

The same approach covers `linux/unaligned.h` versus `asm/unaligned.h` (moved
in 6.12) and the `i2c_driver.probe` signature change in 6.3. The result
builds unmodified on 6.1 through 6.18.

## What the driver exposes

### Formats

Four Bayer RAW10 media bus codes, selected by the HFLIP and VFLIP controls,
which rotate the Bayer phase:

| Flips | Media bus code | V4L2 pixel format |
| --- | --- | --- |
| none | `MEDIA_BUS_FMT_SRGGB10_1X10` | `RG10` |
| HFLIP | `MEDIA_BUS_FMT_SGRBG10_1X10` | `BA10` |
| VFLIP | `MEDIA_BUS_FMT_SGBRG10_1X10` | `GB10` |
| both | `MEDIA_BUS_FMT_SBGGR10_1X10` | `BG10` |

If a capture comes out green or pink, the Bayer order assumed by the
demosaic step does not match the flips set on the subdev.

### Controls

| Control | Notes |
| --- | --- |
| `V4L2_CID_PIXEL_RATE` | read-only, derived from the mode |
| `V4L2_CID_LINK_FREQ` | read-only, 408 MHz |
| `V4L2_CID_VBLANK` / `V4L2_CID_HBLANK` | frame timing; VBLANK also drives the long-exposure multiplier |
| `V4L2_CID_EXPOSURE` | in lines; range depends on VBLANK |
| `V4L2_CID_ANALOGUE_GAIN`, `V4L2_CID_DIGITAL_GAIN` | sensor gain |
| `V4L2_CID_HFLIP`, `V4L2_CID_VFLIP` | changes the Bayer order, as above |
| `V4L2_CID_TEST_PATTERN` plus the four colour components | colour bars without a lens; the fastest way to prove CSI-2 and ISI work |

Focus is a separate sub-device. The AK7375 voice-coil driver
(`CONFIG_VIDEO_AK7375`) binds at I2C `0x0c` and exposes
`V4L2_CID_FOCUS_ABSOLUTE`; the sensor node points at it through
`lens-focus`. There is no closed-loop autofocus in the kernel — on a Pi that
job belongs to libcamera. [`scripts/focus.sh`](../scripts/focus.sh) sets the
DAC directly, and
[`userspace/imx519_capture.py`](../userspace/imx519_capture.py) implements a
contrast-maximising sweep.

## Device-tree binding

Schema: [`bindings/sony,imx519.yaml`](bindings/sony,imx519.yaml). The
required properties are:

| Property | Value |
| --- | --- |
| `compatible` | `sony,imx519` |
| `reg` | `0x1a` |
| `clocks` / `clock-names` | 24 MHz `xclk` |
| `reset-gpios` | Module enable; the driver drives it logical high to power up |
| `VANA-supply` | 2.8 V analogue |
| `VDIG-supply` | 1.05 V digital |
| `VDDL-supply` | 1.8 V I/O |
| endpoint `data-lanes` | `<1 2>` |
| endpoint `link-frequencies` | `408000000` |
| `lens-focus` | phandle to the AK7375 node |

A worked example is in [`../dts`](../dts). Two details there are easy to get
wrong:

- The supplies must not be borrowed from the stock board's camera rails; see
  [the deferred-probe problem](troubleshooting.md#modprobe-imx519-succeeds-but-nothing-probes).
- `reset-gpios` is named after the sensor's XCLR pin, but on a
  Raspberry-Pi-style module it reaches the board as an active-high enable, so
  the flag is `GPIO_ACTIVE_HIGH`. The driver requests it `GPIOD_OUT_HIGH` and
  drives logical `1` in `imx519_power_on()`; see
  [hardware.md](hardware.md#pin-17-is-an-enable-not-a-reset).

## Building it

In-tree, via [`scripts/install-into-kernel.sh`](../scripts/install-into-kernel.sh),
which also installs [`kernel/Kconfig`](../kernel/Kconfig) as
`drivers/media/i2c/Kconfig.imx519` and adds the object to the Makefile:

```
CONFIG_VIDEO_IMX519=m
CONFIG_VIDEO_AK7375=m
```

Out-of-tree, with [`kernel/Makefile`](../kernel/Makefile), against the
**running** kernel's build tree. The ABI must match exactly — this is the
subject of [problem 1 in the README](../README.md#problem-1-the-module-refuses-to-load).

## Upstream status

This is a port, not an upstream submission. An upstream version would need
the version guards removed, the `max_width` parameter replaced by proper
format negotiation with the receiver, and a binding accepted into
`Documentation/devicetree/bindings/media/i2c/`. Useful reading if you want to
take it there: [resources.md](resources.md).
