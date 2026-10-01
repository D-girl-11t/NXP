# Why the Arducam IMX519 does not work on i.MX93 out of the box

The Raspberry Pi overlay at
`https://github.com/raspberrypi/linux/blob/rpi-5.15.y/drivers/media/i2c/imx519.c`
is a V4L2 **sub-device** driver. It only programs the Sony sensor over I2C.
On a Pi the rest of the pipeline is Unicam + the Pi ISP + libcamera. None of
that exists on i.MX93.

## SoC camera block

```
IMX519 (2-lane CSI-2, RAW10 Bayer)
        |
        v
 i.MX93 DWC MIPI CSI-2 host   (80 Mbps – 1.5 Gbps per lane, 2 data lanes)
        |
        v
 i.MX93 ISI gasket + ISI      (max 2K horizontal, 200 Mpixel/s)
        |
        v
 /dev/videoN  (Bayer RAW, no 3A, no YUV)
```

| Resource | Raspberry Pi | i.MX93 |
| --- | --- | --- |
| CSI-2 lanes | 2 (this module) | 2 |
| Hardware ISP | Yes (Unicam/PiSP) | **No** |
| Max useful width | 4656 (full 16 MP) | **2048 (ISI 2K)** |
| Userspace | libcamera / rpicam | media-ctl + v4l2-ctl |
| Autofocus | AK7375 + libcamera AF | AK7375 V4L2 focus_absolute |

## Modes this port exposes by default

`max_width=2048` (module parameter) hides modes the ISI cannot capture:

| Mode | Rate (sensor) | On i.MX93 |
| --- | --- | --- |
| 1920×1080 RAW10 | up to 60 fps | **default still + video** |
| 1280×720 RAW10 | up to 80 fps | supported |
| 2328×1748 (2×2 binned) | 30 fps | exceeds 2K width |
| 3840×2160 | 18 fps | exceeds 2K width |
| 4656×3496 (full 16 MP) | 9 fps | exceeds 2K width |

To experiment with wider modes (they will usually fail at ISI):

```
modprobe imx519 max_width=4656
```

CSI-2 link frequency is **408 MHz** (816 Mbps/lane DDR), which is under the
1.5 Gbps/lane D-PHY limit and under the 200 Mpixel/s ISI pixel-rate budget
(~163 Mpixel/s on the wire for RAW10).

## Connector

### FRDM-i.MX93: use P6, not P7

The board has **two identical-looking 22-pin FPC connectors** (UM12181,
tables 3, 20, 21):

| Connector | Interface | Use |
| --- | --- | --- |
| **P6** | MIPI CSI-2, 2 data lanes | **camera** (RPi-CAM-MIPI) |
| P7 | MIPI DSI, 4 data lanes | display only (Waveshare 7", etc.) |

Both carry 3.3 V on pin 22 and I2C3 (`USB_I2C_SCL`/`SDA`) on pins 20/21, so
a camera in P7 looks plausible and is completely dead. Two pins differ:

| Pin | P6 (CSI) | P7 (DSI) |
| --- | --- | --- |
| 17 | `CSI_nRST` — PCAL6524 **P2_6** | `CTP_RST` — PCAL6524 P2_1 |
| 18 | `CAM_MCLK` (24 MHz from CCM_CLKO3) | `DSI_CTP_nINT` |

In P7 the IMX519 gets **no master clock** and is **never released from
reset**, so it cannot ACK at `0x1a` even though it is powered. `i2cdetect`
shows `--` and the driver never reports a chip-id error, because it does not
get that far.

PCAL6524 numbering: `P2_6` = 16 + 6 = **GPIO 22**, which is what the FRDM DTS
uses (`reset-gpios = <&pcal6524 22 GPIO_ACTIVE_LOW>`).

### Adapter

NXP EVK/FRDM CSI is not a Raspberry Pi 22-pin camera socket at the module
end. You need an adapter such as **XRPi-CAM-MiniSAS** / RPI-CAM-MIPI (the
same one NXP documents for OV5640 and AP1302 on FRDM-i.MX93).

Inspect the FFC itself. Tears or holes in the flex break individual traces —
often the I2C or MCLK lines — and produce the same silent failure.

The Arducam B0371 module has:

- Sony IMX519 at I2C `0x1a`
- AK7375 VCM at I2C `0x0c`
- Onboard 24 MHz crystal and LDOs
- 2 MIPI data lanes + 1 clock lane
- CAM_GPIO used as XCLR / enable

On the 11x11 EVK this port reuses the AP1302 reset GPIO
(`adp5585gpio 0`, active low) and the MiniSAS 2.8 V / 1.8 V rails.

If `i2cdetect` never shows `0x1a`, the adapter is not passing I2C or XCLR is
held in reset — fix hardware before debugging the driver.

## Not possible on i.MX91

i.MX91 **removes the MIPI CSI-2 interface entirely**. Per NXP AN14012
(*i.MX 93 to i.MX 91 Design Compatibility Guide*, §3.2), i.MX91 drops MIPI
CSI, MIPI DSI and LVDS, keeping only the 8-bit parallel YUV/RGB camera and
24-bit parallel RGB display.

| | i.MX93 | i.MX91 |
| --- | --- | --- |
| MIPI CSI-2 | 2-lane + D-PHY | **removed** |
| Parallel camera | 8-bit YUV/RGB | 8-bit YUV/RGB |
| ISI | 2K, 200 Mpixel/s | same |

Upstream confirms it in the driver: the i.MX91 ISI "implements one channel and
one camera input which only can be connected to parallel camera input", so
there is no camera mux to switch between CSI-2 and parallel as on i.MX93.

FRDM-IMX91 therefore has no FPC camera socket; its camera pins are on the
40-pin EXPI header (P11).

The IMX519 is CSI-2 only — RAW10 over two differential lanes, no parallel
output mode. It cannot be attached to i.MX91 without an external CSI-2-to-
parallel bridge on a custom board. For i.MX91, use a parallel/DVP sensor
(OV5640 in parallel mode, MT9M114, …) or a USB UVC camera.

## linux-imx BSP versions

| BSP | CSI driver | `hs-clk-range` in DT |
| --- | --- | --- |
| lf-6.1.y / lf-6.6.y | `drivers/staging/media/imx/dwc-mipi-csi2.c` | **required** (`0x19` for 816 Mbps) |
| lf-6.12.y | `drivers/media/platform/nxp/dwc-mipi-csi2.c` + DPHY RX | ignored (programmed from `V4L2_CID_LINK_FREQ`) |

`cfg-clk-range = <28>` is the 24 MHz CFGCLK encoding used by the EVK AP1302
node. Keep it on 6.1/6.6.
