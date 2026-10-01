# Capturing from the sensor

Once the driver probes, everything else is standard V4L2. The i.MX93 has no
ISP, so `/dev/video0` delivers **Bayer RAW10**, not a YUV webcam stream —
colour is reconstructed on the CPU afterwards.

Install `v4l-utils` and `i2c-tools` on the board first.

## The media graph

Three entities have to be linked and set to the same format:

```
imx519 2-001a  ──▶  mxc-mipi-csi2.0  ──▶  mxc_isi.0  ──▶  /dev/video0
  (sensor subdev)      (CSI-2 receiver)      (ISI)       (capture node)
```

[`setup-pipeline.sh`](../scripts/setup-pipeline.sh) does this. It finds the
media device that actually contains the sensor, resolves the three entity
names (which differ between BSP releases), sets
`SRGGB10_1X10/<width>x<height>` on every pad, and sets the matching pixel
format on the capture node.

```bash
./scripts/setup-pipeline.sh              # 1920x1080 RAW10
./scripts/setup-pipeline.sh 1280 720
./scripts/setup-pipeline.sh 1920 1080 RG10
```

It prints the graph and the sensor's controls, and caches what it found for
the other scripts:

| File | Contents |
| --- | --- |
| `/tmp/imx519-video` | the capture node, e.g. `/dev/video0` |
| `/tmp/imx519-subdev` | the sensor subdev, e.g. `/dev/v4l-subdev0` |
| `/tmp/imx519-media.dev` | the media device |
| `/tmp/imx519-width`, `/tmp/imx519-height` | the configured size |

Inspect the graph by hand with `media-ctl -d /dev/media0 -p`.

## Confirm the sensor is on the bus

```bash
./scripts/i2c-probe.sh 2
```

Bus 2 is LPI2C3 on both boards. Expect `0x1a` for the sensor and `0x0c` for
the focus coil. Both commonly read `--` until `imx519.ko` probes and releases
XCLR, and `UU` once a driver has claimed the address — so scan **after**
loading the module.

## Stills

```bash
./scripts/capture-still.sh shot.raw
```

With no argument it writes a timestamped `frame-*.raw`. The frame comes out
at whatever size `setup-pipeline.sh` configured.

## Video

```bash
./scripts/capture-video.sh 60 clip.raw     # 60 RAW frames
FRAMES=30 FPS=30 ./scripts/capture-video.sh
```

This records concatenated RAW frames. If `ffmpeg` is present on the board it
will also demosaic and encode an MP4; otherwise convert on the host.

## Test pattern

The sensor's internal colour-bar generator is the fastest way to prove the
CSI-2 link and the ISI work, because it needs no lens, no light and no
exposure tuning.

```bash
v4l2-ctl -d "$(cat /tmp/imx519-subdev)" --set-ctrl=test_pattern=1
./scripts/capture-still.sh bars.raw
v4l2-ctl -d "$(cat /tmp/imx519-subdev)" --set-ctrl=test_pattern=0
```

If bars appear but a real scene does not, the problem is optics, exposure or
focus — not the pipeline.

## Exposure and gain

There is no auto-exposure hardware and no 3A daemon, so these are manual.

```bash
SUBDEV="$(cat /tmp/imx519-subdev)"
v4l2-ctl -d "$SUBDEV" --list-ctrls
v4l2-ctl -d "$SUBDEV" --set-ctrl=exposure=1000,analogue_gain=100
```

Exposure is in lines, and its maximum depends on `vblank` — raise `vblank`
first if you need a longer exposure than the control accepts.

## Focus

The AK7375 voice coil is a separate sub-device exposing
`V4L2_CID_FOCUS_ABSOLUTE`.

```bash
./scripts/focus.sh            # print the current value
./scripts/focus.sh 512        # absolute
./scripts/focus.sh +64        # relative step
```

There is no closed-loop autofocus in the kernel. For a contrast-maximising
sweep:

```bash
python3 userspace/imx519_capture.py --jpeg still.jpg --autofocus
```

## Demosaic

```bash
pip install -r userspace/requirements.txt
python3 userspace/raw10_to_png.py --width 1920 --height 1080 shot.raw shot.png
```

[`raw10_to_png.py`](../userspace/raw10_to_png.py) handles both layouts the
ISI can produce: RAW10 in 16-bit little-endian samples (the normal case,
`RG10` / `V4L2_PIX_FMT_SRGGB10`) and packed MIPI RAW10, five bytes per four
pixels, with `--layout packed10`. It can also write a video:

```bash
python3 userspace/raw10_to_png.py --video --fps 30 \
    --width 1920 --height 1080 capture.raw clip.mp4
```

[`imx519_capture.py`](../userspace/imx519_capture.py) wraps the whole
sequence — configure the pipeline, capture, demosaic, write JPEG or MP4:

```bash
python3 userspace/imx519_capture.py --jpeg still.jpg
python3 userspace/imx519_capture.py --mp4 clip.mp4 --seconds 5 --fps 30
python3 userspace/imx519_capture.py --from-raw shot.raw --jpeg out.jpg
```

### Bayer order

The default is RGGB (`RG10`). The HFLIP and VFLIP controls rotate the Bayer
phase, so a flipped capture demosaiced as RGGB comes out green or pink. The
mapping is in [driver.md](driver.md#formats) — either clear the flips on the
subdev or tell the converter the right order.

## Quick reference

| Want | Command |
| --- | --- |
| 720p instead of 1080p | `./scripts/setup-pipeline.sh 1280 720` |
| Colour bars | `v4l2-ctl -d $SUBDEV --set-ctrl=test_pattern=1` |
| Manual exposure | `v4l2-ctl -d $SUBDEV --set-ctrl=exposure=1000,analogue_gain=100` |
| Current format | `v4l2-ctl -d $VIDEO --get-fmt-video` |
| Full graph | `media-ctl -d /dev/media0 -p` |
| 16 MP | not possible through the ISI; see [hardware.md](hardware.md#supported-modes) |
| GStreamer preview | no native RAW10 path; convert frames first |
