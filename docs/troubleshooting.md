# Troubleshooting IMX519 on i.MX93

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

## Graph has AP1302 instead of IMX519

You booted the stock `imx93-11x11-evk.dtb`. Use
`imx93-11x11-evk-imx519.dtb` (`setenv fdtfile imx93-11x11-evk-imx519.dtb`).

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
