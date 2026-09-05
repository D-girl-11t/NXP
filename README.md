# IMX519 on NXP i.MX93

Make the **Arducam 16MP autofocus camera** (Sony IMX519, typically SKU B0371)
work on an **NXP i.MX93** board (11x11 EVK or FRDM) and capture stills and
video.

The Raspberry Pi driver at
[`drivers/media/i2c/imx519.c`](https://github.com/raspberrypi/linux/blob/rpi-5.15.y/drivers/media/i2c/imx519.c)
is not enough on its own: i.MX93 has a different CSI-2 host, no Pi ISP, and
an ISI that cannot take the sensor's full 4656×3496 mode. This tree ports
that driver, adds i.MX93 device trees, and ships capture helpers.

## What you get

- V4L2 sub-device driver (I2C `0x1a`, RAW10, 2 CSI-2 lanes, 408 MHz link)
- Default **1920×1080** and **1280×720** modes (ISI 2K limit)
- Device trees that **replace the stock AP1302** camera on MiniSAS CSI
- AK7375 voice-coil node for manual autofocus
- `media-ctl` / `v4l2-ctl` scripts for stills and RAW video
- Optional Python demosaic (`userspace/raw10_to_png.py`)

There is **no hardware ISP** on i.MX93. Captures are Bayer RAW. Colour images
come from the demosaic tool or ffmpeg, not from `/dev/video0` as YUYV.

**Hands-on walkthrough (laptop + board):** [docs/bringup-steps.md](docs/bringup-steps.md)

**Windows PC:** [docs/windows.md](docs/windows.md) — PuTTY on COMx + WSL2 to build the kernel. You cannot compile linux-imx in PowerShell.

## Hardware

1. i.MX93 11x11 EVK or FRDM-i.MX93 running NXP linux-imx (**lf-6.6.y** is the
   primary target; lf-6.1.y and lf-6.12.y notes are in
   [docs/hardware.md](docs/hardware.md)).
2. Arducam IMX519 16MP AF camera (Pi 22-pin).
3. **RPi-CAM → MiniSAS adapter** (NXP XRPi-CAM-MiniSAS or equivalent). The
   EVK CSI connector is not a Raspberry Pi camera socket.

```
IMX519  --2-lane CSI-2-->  i.MX93 CSI host  -->  ISI  -->  /dev/videoN (RG10)
   I2C 0x1a / VCM 0x0c on LPI2C3
```

See [docs/hardware.md](docs/hardware.md) for rails, GPIOs, and why 16 MP
full-resolution cannot go through ISI.

## Kernel

### Option A — copy into linux-imx

```bash
./scripts/install-into-kernel.sh /path/to/linux-imx
cd /path/to/linux-imx
make imx_v8_defconfig
./scripts/kconfig/merge_config.sh -m .config arch/arm64/configs/imx519.config
make olddefconfig
make -j"$(nproc)" Image modules dtbs
```

Boot with:

```
setenv fdtfile imx93-11x11-evk-imx519.dtb
saveenv
```

Enable at least:

```
CONFIG_VIDEO_IMX519=m
CONFIG_VIDEO_AK7375=m
```

(`configs/imx519.cfg` is the fragment.)

### Option B — out-of-tree module

If the DTB is already on the board:

```bash
cd kernel
make -C /lib/modules/$(uname -r)/build M=$PWD modules
sudo make -C /lib/modules/$(uname -r)/build M=$PWD modules_install
sudo depmod -a
sudo modprobe imx519
```

### Option C — Yocto

```bash
./scripts/sync-yocto.sh
# add yocto/meta-imx519 to BBLAYERS
# IMAGE_INSTALL:append = " imx519-tools"
# KERNEL_DEVICETREE:append = " freescale/imx93-11x11-evk-imx519.dtb"
bitbake linux-imx
```

Details in [yocto/README.md](yocto/README.md).

## Capture

On the board, with `v4l-utils` installed:

```bash
# 1. Confirm the sensor and VCM ACK on CSI I2C (usually bus 2)
./scripts/i2c-probe.sh 2

# 2. Wire the media graph at 1080p RAW10
./scripts/setup-pipeline.sh 1920 1080

# 3. Optional: colour bars (proves CSI/ISI without a lens)
#    v4l2-ctl -d "$(cat /tmp/imx519-subdev)" --set-ctrl=test_pattern=1

# 4. Still
./scripts/capture-still.sh shot.raw

# 5. Short RAW clip (60 frames) + ffmpeg MP4 if ffmpeg is present
./scripts/capture-video.sh 60 clip.raw

# 6. Manual focus (AK7375 DAC)
./scripts/focus.sh 512
```

Demosaic a still (host or board, needs numpy + Pillow):

```bash
pip install -r userspace/requirements.txt
python3 userspace/raw10_to_png.py --width 1920 --height 1080 shot.raw shot.png
```

Typical pipeline after `setup-pipeline.sh`:

```
imx519 2-001a  →  mxc-mipi-csi2.0  →  mxc_isi.0  →  /dev/video0
```

| Want | Command |
| --- | --- |
| 720p | `./scripts/setup-pipeline.sh 1280 720` then capture |
| Test pattern | `v4l2-ctl -d $SUBDEV --set-ctrl=test_pattern=1` (1 = colour bars) |
| Exposure | `v4l2-ctl -d $SUBDEV --set-ctrl=exposure=1000,analogue_gain=100` |
| GStreamer preview of RAW | not native; convert frames first, then `gst-play-1.0 shot.png` |

## Layout

```
kernel/imx519.c          Ported sensor driver (GPL-2.0, from Arducam/RPi)
dts/                     EVK + FRDM board trees
configs/imx519.cfg       Kernel fragment
scripts/                 Probe, pipeline, still, video, focus, install
userspace/raw10_to_png.py
yocto/meta-imx519        Optional layer
docs/                    Hardware limits and troubleshooting
```

## Credits

Sensor register tables and original V4L2 driver:
Copyright (C) 2021 Arducam Technology co., Ltd., based on the Sony IMX477
driver, Copyright (C) 2020 Raspberry Pi (Trading) Ltd. License: GPL-2.0.
