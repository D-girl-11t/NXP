# Step-by-step: IMX519 on i.MX93 (laptop + board)

Work happens in **two places**:

| Where | What you do |
| --- | --- |
| **Laptop** | Patch linux-imx, build kernel + DTB + module, copy them onto the SD card |
| **Board** | Change U-Boot `fdtfile`, boot, run capture scripts |

You do **not** edit the Raspberry Pi `imx519.c` on GitHub. You copy the ported driver from this repo into NXP’s kernel tree.

**On a Windows PC:** do not follow the Linux `picocom` / `/dev/ttyUSB0` commands below. Use [windows.md](windows.md) (PuTTY + WSL2) instead.

---

## 0. What must be plugged in

1. **Power** the i.MX93 board from its supply (USB-C/barrel — not only the debug USB).
2. **Debug UART** from the board to the laptop (USB debug / micro-USB console). This is how you see U-Boot and Linux.
   - EVK: typically `/dev/ttyUSB0` or `/dev/ttyACM0` at **115200 8N1**.
3. **Ethernet** (or USB gadget SSH) so you can copy files after first boot. Optional if you only use a serial console and an SD card.
4. **Camera**: Arducam IMX519 (22-pin Pi cable) → **RPi-CAM to MiniSAS adapter** → **MiniSAS CSI** on the i.MX93.
   - The CSI connector on the EVK is **not** a Raspberry Pi camera socket. Without the adapter the sensor will never appear on I2C.

Power off when seating the CSI cable. Contacts face the way the stock AP1302 module did.

---

## 1. On the laptop — serial console

```bash
sudo apt install picocom
sudo picocom -b 115200 /dev/ttyUSB0
```

If that port is busy, try `/dev/ttyACM0`. You should see U-Boot or a Linux login after the board boots.

---

## 2. On the laptop — get this repo and linux-imx

Use the **same kernel version** as the image already on the board (`uname -r` after it boots, e.g. `6.6.52-lts`).

```bash
# this project (ported driver + DTS + scripts)
git clone <this-repo-url> imx519-imx93
cd imx519-imx93

# NXP kernel (example: lf-6.6.y — match your BSP)
git clone -b lf-6.6.52-2.2.0 https://github.com/nxp-imx/linux-imx.git
```

If you already have a Yocto `tmp/work-shared/.../linux-imx` or a BSP `linux-imx` folder, use **that** instead of cloning.

---

## 3. On the laptop — what to change (and where)

Run the installer (it copies files for you):

```bash
./scripts/install-into-kernel.sh /path/to/linux-imx
```

That changes **linux-imx**, not the board:

| File in linux-imx | Change |
| --- | --- |
| `drivers/media/i2c/imx519.c` | **New** — ported sensor driver |
| `drivers/media/i2c/Kconfig` | Sources IMX519 Kconfig |
| `drivers/media/i2c/Makefile` | `obj-$(CONFIG_VIDEO_IMX519) += imx519.o` |
| `arch/arm64/boot/dts/freescale/imx93-11x11-evk-imx519.dts` | **New board DTB** — removes AP1302, adds IMX519 @ `0x1a` |
| `arch/arm64/boot/dts/freescale/Makefile` | Builds `imx93-11x11-evk-imx519.dtb` |
| `.config` | `CONFIG_VIDEO_IMX519=m` and `CONFIG_VIDEO_AK7375=m` |

If your board is **FRDM-i.MX93**, use `dts/imx93-11x11-frdm-imx519.dts` the same way (copy next to the other FRDM dts files).

**Do not** keep using `imx93-11x11-evk.dtb`. That DTB still describes the AP1302 ISP camera, so Linux will never probe IMX519.

---

## 4. On the laptop — build

You need an aarch64 cross toolchain (Ubuntu):

```bash
sudo apt install gcc-aarch64-linux-gnu bc bison flex libssl-dev device-tree-compiler
```

```bash
cd /path/to/linux-imx
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

make imx_v8_defconfig
./scripts/kconfig/merge_config.sh -m .config arch/arm64/configs/imx519.config
make olddefconfig

# confirm these are set
grep -E 'VIDEO_IMX519|VIDEO_AK7375' .config
# CONFIG_VIDEO_IMX519=m
# CONFIG_VIDEO_AK7375=m

make -j"$(nproc)" Image modules dtbs
```

Outputs you will copy:

- `arch/arm64/boot/Image`
- `arch/arm64/boot/dts/freescale/imx93-11x11-evk-imx519.dtb`
- `drivers/media/i2c/imx519.ko` (and `ak7375.ko` if built as a module)

---

## 5. Copy onto the SD card (still on the laptop)

Put the EVK SD card in the laptop (or mount the board’s eMMC partitions if you boot from eMMC).

Typical layout:

- **partition 1 (FAT)** — `Image`, `*.dtb`  (sometimes named `boot`)
- **partition 2 (ext4)** — rootfs `/lib/modules/...`

```bash
# adjust /dev/sdX and mount points to match your PC
sudo mkdir -p /mnt/boot /mnt/root
sudo mount /dev/sdX1 /mnt/boot
sudo mount /dev/sdX2 /mnt/root

sudo cp arch/arm64/boot/Image /mnt/boot/
sudo cp arch/arm64/boot/dts/freescale/imx93-11x11-evk-imx519.dtb /mnt/boot/

# modules: either full install, or just the two .ko files
sudo make ARCH=arm64 INSTALL_MOD_PATH=/mnt/root modules_install

sudo umount /mnt/boot /mnt/root
```

Also copy this repo’s `scripts/` folder onto the rootfs, e.g. `/home/root/imx519-imx93/scripts`.

Put the SD card back in the board.

---

## 6. On the board — tell U-Boot to use the new DTB

Power on, hit a key in picocom to stop at `=>`.

**EVK:**

```
setenv fdtfile imx93-11x11-evk-imx519.dtb
saveenv
boot
```

**FRDM:**

```
setenv fdtfile imx93-11x11-frdm-imx519.dtb
saveenv
boot
```

Some NXP images load DTB from `mmc` with a name in `fdt_file` instead of `fdtfile`. If `setenv fdtfile` seems ignored:

```
printenv fdtfile fdt_file
setenv fdt_file imx93-11x11-evk-imx519.dtb
saveenv
```

The DTB file must exist in the same directory U-Boot already loads `imx93-11x11-evk.dtb` from (usually `/boot` on FAT).

---

## 7. On the board — load driver and capture

Login (NXP images often `root` with no password).

```bash
uname -r
dmesg | grep -i imx519
modprobe imx519
modprobe ak7375     # autofocus coil; OK if this fails on a no-AF module

# I2C: IMX519 must ACK at 0x1a (bus is usually 2 = LPI2C3)
i2cdetect -y 2
```

You want `1a` on that scan. If it is `--`, the adapter/reset/cable is wrong — do not debug software yet.

```bash
cd /home/root/imx519-imx93   # wherever you copied the scripts
./scripts/setup-pipeline.sh 1920 1080
./scripts/capture-still.sh shot.raw
./scripts/capture-video.sh 60 clip.raw
./scripts/focus.sh 512
```

Prove CSI with colour bars (no lens needed):

```bash
v4l2-ctl -d "$(cat /tmp/imx519-subdev)" --set-ctrl=test_pattern=1
./scripts/capture-still.sh bars.raw
```

Copy `shot.raw` to the laptop and convert:

```bash
python3 userspace/raw10_to_png.py --width 1920 --height 1080 shot.raw shot.png
```

i.MX93 has **no ISP**. `/dev/video0` is Bayer RAW, not a JPEG camera.

---

## If something fails

| You see | Change this |
| --- | --- |
| Still `ap1302` in `dmesg` / `media-ctl -p` | Wrong DTB — step 6 (`fdtfile`) |
| `imx519: failed to read chip id` | Cable/adapter/XCLR — step 0; `i2cdetect -y 2` |
| `xclk frequency not supported` | DTS clock node (already 24 MHz dummy in our DTS) |
| Stream timeout, no frames | `hs-clk-range` is `0x19` in our DTS; stock AP1302 used `0x2b` — you must use **our** DTB |
| Want 16 MP | Not possible through i.MX93 ISI (2K width max). Stay at 1080p/720p |

More detail: `docs/troubleshooting.md`.
