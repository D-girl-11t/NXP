# IMX519 16 MP autofocus camera on NXP FRDM-i.MX93 — bring-up log

A step-by-step record of what we set out to do, what broke, and how each
problem was fixed. Written from an actual bring-up on real hardware, so every
error message and path below is one that occurred.

---

## The goal

Make an **Arducam 16 MP autofocus camera** (Sony **IMX519**, SKU B0371 — sensor
at I2C `0x1a`, AK7375 focus coil at `0x0c`) capture images on an **NXP
FRDM-i.MX93** board running NXP's `linux-imx` **6.18.2** BSP, and be able to
take stills and video from it.

Board: `imx93-11x11-lpddr4x-frdm`, `uname -r` = `6.18.2-1.0.0-gf49f45233f7b`.

## The problem

Nothing about this camera is supported out of the box, for three separate
reasons.

**1. The stock board expects a different camera.** The FRDM BSP ships a device
tree describing NXP's **AP1302** ISP module on the CSI connector. The IMX519 is
not in it, so Linux never looks for it.

**2. The only existing IMX519 driver is written for Raspberry Pi.** The driver
in the Raspberry Pi kernel assumes Unicam plus the Pi's hardware ISP and
libcamera. It exposes a second "embedded data" metadata pad that only Unicam
understands, and it defaults to the sensor's full 4656×3496 mode.

**3. i.MX93 cannot take that pipeline.** It has a Synopsys DesignWare CSI-2
receiver feeding an ISI, **no hardware ISP at all**, and the ISI is limited to
about 2K horizontal. So 16 MP cannot be captured, and frames arrive as **Bayer
RAW10** rather than YUV — colour has to be reconstructed in software.

```
IMX519 (2-lane CSI-2, RAW10)  ->  i.MX93 DWC CSI-2  ->  ISI  ->  /dev/videoN (RG10)
   I2C 0x1a / VCM 0x0c on LPI2C3 (= /dev/i2c-2)
```

---

## What we did

### 1. Ported the driver to i.MX93

Took the Raspberry Pi `imx519.c` and adapted it:

- Removed the Unicam embedded-data metadata pad, leaving a single `IMAGE_PAD`.
  This also removed the dependency on `MEDIA_BUS_FMT_SENSOR_DATA`, which no
  longer exists in kernel 6.18.
- Updated to current V4L2 APIs (`v4l2_subdev_state_get_format`,
  `linux/unaligned.h`) with version guards so it still builds on 6.1–6.12.
- Made **1920×1080** the default mode and added 1280×720, because the ISI
  cannot accept wider, and set the CSI-2 link frequency to **408 MHz**
  (816 Mbps/lane).

### 2. Wrote a FRDM device tree

`dts/imx93-11x11-frdm-imx519.dts` includes the stock FRDM tree and then:

- deletes the AP1302 node,
- adds `imx519@1a` and `ak7375@c` on `lpi2c3`,
- wires the sensor endpoint into the 6.18 CSI graph via `mipi_csi_in`,
- declares the reset line as `<&pcal6524 22 GPIO_ACTIVE_LOW>` — PCAL6524 `P2_6`,
  which is `CSI_nRST` on connector P6.

### 3. Fixed the kernel build

Two build failures, both from a stale copy of the project on the laptop:

- `Label or path isi_0 not found` — the EVK device tree being built was the
  old lf-6.6 variant. FRDM does not need it, so we removed that dtb target
  from `arch/arm64/boot/dts/freescale/Makefile`.
- `MEDIA_BUS_FMT_SENSOR_DATA undeclared` — the laptop's `imx519.c` was still
  the Pi version. Defined the constant locally to get the build through.

### 4. Hit the real blocker: a kernel ABI mismatch

The module refused to load:

```
insmod: ERROR: could not insert module ... Invalid parameters
modprobe: ERROR: could not insert 'imx519': Invalid argument

imx519: disagrees about version of symbol _dev_info
imx519: Unknown symbol i2c_register_driver (err -22)
```

`depmod -a` cannot fix this. Comparing vermagic showed why:

| | vermagic |
| --- | --- |
| our `imx519.ko` | `6.18.2-gf49f45233f7b-dirty` |
| running kernel | `6.18.2-1.0.0-gf49f45233f7b` |

The module had been compiled against a different `.config` and
`Module.symvers` than the Yocto kernel on the board, so with
`CONFIG_MODVERSIONS=y` the loader rejected every symbol CRC.

`/lib/modules/$(uname -r)/build` did not exist, so there were **no kernel
headers on the board** and the module could not be rebuilt there. The only
option was to replace the kernel and the modules **together**.

### 5. Built and installed a matching kernel

```bash
cd ~/linux-imx
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make -j"$(nproc)" Image modules dtbs
make -s kernelrelease          # 6.18.2-gf49f45233f7b-dirty
```

### 6. Got a network to the board

`udhcpc` never got a lease because the board was cabled directly to the laptop
with no DHCP server. Static addresses fixed it:

```bash
# laptop
sudo ip addr add 192.168.50.1/24 dev eno1
# board
ip addr add 192.168.50.2/24 dev eth0
ip link set eth0 up
```

Note this does not survive a reboot — re-apply it, or drop a
`systemd-networkd` file in place.

### 7. Swapped in the new kernel

```bash
# laptop
scp arch/arm64/boot/Image root@192.168.50.2:/tmp/
scp ~/imx519-mods.tar.gz  root@192.168.50.2:/tmp/

# board — keep a rescue kernel on the FAT partition
tar xzf /tmp/imx519-mods.tar.gz -C /lib/modules/
cp /run/media/boot-mmcblk0p1/Image /run/media/boot-mmcblk0p1/Image.stock
cp /tmp/Image /run/media/boot-mmcblk0p1/Image
sync && reboot
```

`Image.stock` matters: if a new kernel does not boot, U-Boot can only load a
rescue image from the FAT partition, not from the rootfs.

U-Boot's `fdtfile` could not be changed (`setenv` run inside Linux does
nothing, and `fw_setenv` was unavailable), so instead we **overwrote the
filename U-Boot already loads**, `imx93-11x11-frdm.dtb`, with our blob.

After the reboot, `uname -r` read `6.18.2-gf49f45233f7b-dirty` and
`modprobe imx519` returned 0 with no symbol errors.

### 8. Found the driver silently not binding

`modprobe` succeeded but printed nothing at all — no chip id, no error. The
module had registered but the device never got a probe call:

```bash
mount -t debugfs none /sys/kernel/debug
cat /sys/kernel/debug/devices_deferred
```

```
regulator-vddo  platform: supplier 2-0034 not ready
2-001a  i2c: supplier regulator-vddo not ready
```

`2-0034` is `adp5585_isp`, an ADP5585 I/O expander that gates `AVDD_2V8`,
`VDDIO_1V8` and `DVDD` — and it lives **on NXP's AP1302 camera module**, not on
the FRDM board. Our device tree had borrowed those rails, so with an Arducam
attached instead, the expander never ACKed, its regulators never registered,
and the sensor waited behind them forever.

### 9. Gave the camera its own supplies

The Arducam B0371 has onboard LDOs and only needs the 3.3 V that P6 pin 22
supplies unconditionally. So the DTS now declares its own always-on fixed
regulators — `reg_imx519_vana`, `reg_imx519_vdig`, `reg_imx519_vddl` — instead
of referencing `reg_avdd_2v8` / `reg_vddio_1v8`.

Rebuilt the dtb, copied it over `imx93-11x11-frdm.dtb`, rebooted, and verified:

```bash
ls -d /proc/device-tree/regulator-imx519-*
```

The four `regulator-*` entries stay in `devices_deferred` afterwards. That is
harmless — they belong to the camera module we are not using.

### 10. The driver now probes

```
imx519 2-001a: failed to read chip id 519, with error -5
```

`2-001a` left `devices_deferred`, `0x0c` shows `UU`, and the driver ran its
full probe: enabled the regulators, started the 24 MHz clock, released
`CSI_nRST`, and tried to read register `0x0016`. Error `-5` is `EIO` — nothing
on the bus answered. **Every software layer is correct from this point on.**

### 11. Identified the hardware faults

- The camera was plugged into **P7**, the MIPI **DSI** connector. P6 and P7 are
  both 22-pin 0.5 mm FPC sockets and look identical, and both carry 3.3 V on
  pin 22 and I2C3 on pins 20/21 — so it looks plausible and does nothing.
  On P7, pin 18 is `DSI_CTP_nINT` instead of `CAM_MCLK` and pin 17 is
  `CTP_RST` instead of `CSI_nRST`, so the sensor gets **no 24 MHz master
  clock** and is **never released from reset**. It cannot ACK. The data pairs
  also face a DSI *transmitter*, which can never receive video.
  (NXP's own UM12181 contradicts itself here: §3.3.1 says P7, while §2.14 and
  Tables 20/21 make P6 the only possibility. P6 is correct.)
- **P6's black FPC latch is broken**, so the cable cannot be clamped.
- The flex cable has holes in it, which can break individual traces.

---

## Current state

Working and verified:

- `uname -r` = `6.18.2-gf49f45233f7b-dirty`, matching the module
- `modprobe imx519` loads cleanly, no symbol errors
- `cat /proc/device-tree/model` → `NXP FRDM-i.MX93 with Arducam IMX519`
- `imx519@1a` linked to `csi@4ae00000` in the device tree, AP1302 gone
- no deferred probe; the driver reaches the sensor over I2C
- AK7375 bound at `2-000c`

Remaining: the physical link. The sensor must be on **P6**, with an intact
cable, held with enough contact force.

### Ways forward on the connector

1. **Transplant from P7.** P7 is useless for a camera, so its latch — or the
   whole connector — is a free donor. Swapping just the actuator needs no heat.
2. **Shim and clamp.** Add a layer of tape to the back of the cable end to
   thicken it, insert fully and square, then press a firm pad down over the
   contacts. I2C will likely work; 816 Mbps MIPI probably will not be reliable.
3. **Replace the connector.** 22-pin, 0.5 mm, right-angle, ZIF. Get the exact
   part from the FRDM-IMX93 design files BOM rather than matching specs.
   Molex `52435-2233` is the 22-circuit right-angle **top**-contact option;
   `52437-2233` is the bottom-contact equivalent.
4. **Use another board.** `dts/imx93-11x11-evk-imx519.dts` covers the 11x11 EVK,
   which uses MiniSAS and does not involve P6 at all.

### Once the sensor answers

```bash
./scripts/setup-pipeline.sh 1920 1080
./scripts/capture-still.sh shot.raw
./scripts/focus.sh 512
python3 userspace/raw10_to_png.py --width 1920 --height 1080 shot.raw shot.png
```

There is no ISP, so `/dev/video0` is Bayer RAW (`RG10`), not a YUV webcam.
Colour comes from the demosaic step.

---

## Where the files live

### On the laptop

| Path | What |
| --- | --- |
| `~/imx519-nxp-link/` | this project (driver, DTS, scripts, docs) |
| `~/linux-imx/` | NXP kernel with our files copied in |
| `~/linux-imx/arch/arm64/boot/Image` | the kernel now booting |
| `~/linux-imx/drivers/media/i2c/imx519.ko` | the module |

### On the board

| Path | What |
| --- | --- |
| `/lib/modules/6.18.2-gf49f45233f7b-dirty/extra/` | `imx519.ko`, `ak7375.ko` |
| `/run/media/boot-mmcblk0p1/Image` | custom kernel (`Image.stock` = rescue) |
| `/run/media/boot-mmcblk0p1/imx93-11x11-frdm.dtb` | our dtb (`.orig` = stock) |

---

## Useful diagnostics

```bash
# is the module's ABI the same as the running kernel?
./scripts/check-ko-abi.sh

# retry the probe after a mechanical adjustment, no reboot needed
echo 2-001a > /sys/bus/i2c/drivers/imx519/bind 2>/dev/null; dmesg | tail -3

# what is the driver waiting on?
mount -t debugfs none /sys/kernel/debug 2>/dev/null
cat /sys/kernel/debug/devices_deferred

# is the sensor on the bus? (only meaningful after the driver probes)
i2cdetect -y 2
```

More detail in [docs/troubleshooting.md](docs/troubleshooting.md) and
[docs/hardware.md](docs/hardware.md).
