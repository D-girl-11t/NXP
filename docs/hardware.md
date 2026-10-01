# i.MX93 camera hardware

What the SoC can and cannot do with this sensor, and how the module is
wired. This is the background for the design choices in
[driver.md](driver.md) and the device trees in [`../dts`](../dts).

## Camera path

```
IMX519 (2-lane CSI-2, RAW10 Bayer)
        │
        ▼
 i.MX93 DWC MIPI CSI-2 host      80 Mbps – 1.5 Gbps per lane, 2 data lanes
        │
        ▼
 i.MX93 ISI gasket + ISI         max 2K horizontal, 200 Mpixel/s
        │
        ▼
 /dev/videoN                     Bayer RAW, no 3A, no YUV
```

The i.MX93 has **no hardware ISP**. The ISI (Image Sensing Interface) is a
capture and scaling block: it can crop, scale, and convert pixel formats,
but it does not demosaic, and there is no auto-exposure or auto-white-balance
hardware. Colour reconstruction happens in software.

## Compared with a Raspberry Pi

The sensor is the same; everything around it differs.

| Resource | Raspberry Pi | i.MX93 |
| --- | --- | --- |
| CSI-2 receiver | Unicam | Synopsys DesignWare CSI-2 + ISI |
| CSI-2 lanes | 2 | 2 |
| Hardware ISP | Yes (PiSP) | **No** |
| Max useful width | 4656 (full 16 MP) | **2048 (ISI 2K limit)** |
| Userspace stack | libcamera / `rpicam-*` | `media-ctl` + `v4l2-ctl` |
| Autofocus | AK7375 driven by libcamera AF | AK7375 via `V4L2_CID_FOCUS_ABSOLUTE` |
| Pixel format out | YUV or JPEG | Bayer RAW10 (`RG10`) |

This is why the Raspberry Pi driver cannot be used unchanged: it is written
against the Pi half of this table.

## Supported modes

The driver's `max_width` module parameter defaults to 2048, which hides the
modes the ISI cannot capture.

| Sensor mode | Sensor rate | On i.MX93 |
| --- | --- | --- |
| 1920×1080 RAW10 | up to 60 fps | **default for stills and video** |
| 1280×720 RAW10 | up to 80 fps | supported |
| 2328×1748 (2×2 binned) | 30 fps | exceeds the 2K width limit |
| 3840×2160 | 18 fps | exceeds the 2K width limit |
| 4656×3496 (full 16 MP) | 9 fps | exceeds the 2K width limit |

To experiment with the wider modes — they will normally fail at the ISI:

```bash
modprobe imx519 max_width=4656
```

### Link budget

The CSI-2 link frequency is **408 MHz**, which is 816 Mbps per lane DDR.
That sits comfortably under the 1.5 Gbps/lane D-PHY ceiling, and at RAW10
over two lanes it works out to roughly 163 Mpixel/s on the wire — inside the
ISI's 200 Mpixel/s budget.

## Module

The Arducam B0371 carries:

- Sony IMX519 sensor at I2C `0x1a`
- AK7375 voice-coil focus driver at I2C `0x0c`
- Onboard 24 MHz crystal and LDOs
- 2 MIPI data lanes plus 1 clock lane
- A `CAM_GPIO` line used as XCLR / enable

Because the module regulates its own rails, it only needs the 3.3 V the
camera connector provides. That is why the device trees here declare
always-on fixed regulators rather than borrowing the stock board's gated
camera supplies — see
[the deferred-probe problem](troubleshooting.md#modprobe-imx519-succeeds-but-nothing-probes).

## Connectors

### Adapter

The FRDM board does not expose a Raspberry Pi camera socket at the module
end, so a Raspberry-Pi-to-NXP camera adapter is required — the same
**RPI-CAM-MIPI** / **XRPi-CAM-MiniSAS** class of board that NXP documents
for its own OV5640 and AP1302 modules.

### Which socket

The board has two 22-pin 0.5 mm FPC connectors that look identical
(UM12181 tables 3, 20 and 21):

| Connector | Interface | Purpose |
| --- | --- | --- |
| **P6** | MIPI CSI-2, 2 data lanes | **camera** |
| P7 | MIPI DSI, 4 data lanes | display panels only |

The camera belongs on **P6**. Both connectors carry 3.3 V on pin 22 and I2C3
on pins 20 and 21, but two pins differ and they are the two that matter:

| Pin | P6 (CSI) | P7 (DSI) |
| --- | --- | --- |
| 17 | `CSI_nRST` — PCAL6524 **P2_6** | `CTP_RST` — PCAL6524 P2_1 |
| 18 | `CAM_MCLK` (24 MHz from CCM_CLKO3) | `DSI_CTP_nINT` |

Only P6 supplies the 24 MHz master clock and the camera reset line, and only
P6's data pairs face a CSI-2 *receiver*.

PCAL6524 GPIO numbering: `P2_6` is 16 + 6 = **line 22**, which is what the
FRDM device tree uses:

```
reset-gpios = <&pcal6524 22 GPIO_ACTIVE_LOW>;
```

## BSP differences

This project targets `linux-imx` **6.18.2**, which is what the FRDM board
runs. The CSI-2 receiver driver and its device-tree contract changed across
earlier NXP releases, so a device tree written for one will not build against
the other.

| BSP | CSI-2 driver | `hs-clk-range` in DT |
| --- | --- | --- |
| lf-6.1.y, lf-6.6.y | `drivers/staging/media/imx/dwc-mipi-csi2.c` | **required** — `0x19` for 816 Mbps |
| lf-6.12.y and later | `drivers/media/platform/nxp/dwc-mipi-csi2.c` plus a DPHY RX driver | ignored; programmed from `V4L2_CID_LINK_FREQ` |

The graph node names changed too: lf-6.6 uses `isi_0` and `cameradev`, while
6.12 and later use `mipi_csi_in` / `mipi_csi_out` / `isi_in`. Mixing them
produces `Label or path isi_0 not found` at `make dtbs` time.

On 6.1 and 6.6 the endpoint also needs `cfg-clk-range = <28>`, the 24 MHz
CFGCLK encoding NXP's own camera nodes use.

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

The upstream ISI driver confirms it: the i.MX91 ISI "implements one channel
and one camera input which only can be connected to parallel camera input",
so unlike i.MX93 there is no camera mux to select between CSI-2 and parallel.
FRDM-IMX91 therefore has no FPC camera socket; its camera pins are on the
40-pin EXPI header (P11).

The IMX519 is CSI-2 only — RAW10 over two differential lanes, with no
parallel output mode — so it cannot attach to i.MX91 without an external
CSI-2-to-parallel bridge. For i.MX91, use a parallel/DVP sensor (OV5640 in
parallel mode, MT9M114) or a USB UVC camera.
