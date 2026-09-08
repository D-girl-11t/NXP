# Step-by-step: IMX519 on i.MX93 (laptop + board)

Work happens in **two places**:

| Where | What you do |
| --- | --- |
| **Laptop** | Patch linux-imx, build kernel + DTB + module, copy them onto the SD card |
| **Board** | Change U-Boot `fdtfile`, boot, run capture scripts |

You do **not** edit the Raspberry Pi `imx519.c` on GitHub. You copy the ported driver from this repo into NXP’s kernel tree.

**On a Windows PC:** do not follow the Linux `picocom` / `/dev/ttyUSB0` commands below. Use [windows.md](windows.md) (PuTTY + WSL2) instead.

**Dual-boot (Windows + Ubuntu):** boot Ubuntu and follow this file as written. Skip WSL and PuTTY. Use `picocom` on `/dev/ttyUSB0` or `/dev/ttyACM0`, and copy `Image` / `.dtb` with a normal SD-card mount.

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

## 2. On the laptop — put the camera driver into NXP’s kernel

You need **two folders** on the laptop. Step 2 is only: copy from folder A into folder B.

```
Folder A  imx519-imx93/     this project (driver + DTS + scripts)
Folder B  linux-imx/        NXP’s kernel source (what actually boots the board)
```

The board cannot use folder A by itself. Linux on i.MX93 is built from folder B. The script copies our IMX519 files into folder B so the next `make` includes the camera.

### 2a. Folder A — this project

If you already have this repo (it contains `README.md`, `kernel/imx519.c`, and `scripts/`), that folder **is** folder A. `cd` into it.

If you still need it, clone or copy it to your home directory and call it `imx519-imx93`.

### 2b. Folder B — NXP kernel (`linux-imx`)

This is **not** the Raspberry Pi kernel. It is NXP’s kernel.

On the board (picocom login), run:

```bash
uname -r
```

Example output: `6.6.52-lts`. You want linux-imx from the same BSP (lf-6.6.y if you see 6.6.x).

**If you do not already have linux-imx** (Yocto downloads or an NXP BSP tarball):

```bash
cd ~
git clone -b lf-6.6.52-2.2.0 https://github.com/nxp-imx/linux-imx.git
```

If clone by tag fails, pick a `lf-6.6*` branch from https://github.com/nxp-imx/linux-imx/branches — stay on 6.6 if `uname -r` is 6.6.x.

**If you already have it** (common with Yocto):

```text
~/imx-yocto-bsp/tmp/work-shared/imx93-11x11-lpddr4x-evk/kernel-source
```

or a folder named `linux-imx` inside the NXP BSP. That folder is folder B. Do not clone a second copy.

Folder B is correct if this exists:

```bash
ls ~/linux-imx/drivers/media/i2c
```

### 2c. Run the copy script (the only command in “step 2”)

Replace the path with **your** folder B. Example: kernel cloned as `~/linux-imx`.

```bash
cd ~/imx519-imx93
./scripts/install-into-kernel.sh ~/linux-imx
```

`~/linux-imx` is a real path, not a name you type literally if your kernel lives somewhere else. If Yocto’s kernel is elsewhere:

```bash
./scripts/install-into-kernel.sh ~/imx-yocto-bsp/tmp/work-shared/imx93-11x11-lpddr4x-evk/kernel-source
```

You should see copy messages for `imx519.c` and the EVK `.dts`. That is success. Nothing is installed on the board yet.

What the script changes **inside linux-imx**:

| File in linux-imx | What happened |
| --- | --- |
| `drivers/media/i2c/imx519.c` | New camera driver |
| `drivers/media/i2c/Makefile` | Builds `imx519.o` |
| `arch/arm64/boot/dts/freescale/imx93-11x11-evk-imx519.dts` | New board file (IMX519 instead of AP1302) |
| `arch/arm64/boot/dts/freescale/Makefile` | Builds `imx93-11x11-evk-imx519.dtb` |

If the board is **FRDM-i.MX93**, also copy `dts/imx93-11x11-frdm-imx519.dts` into that same `freescale/` directory.

**Do not** keep using `imx93-11x11-evk.dtb`. That DTB still describes AP1302.

Next is **step 3** (compile). You have not flashed anything yet.

---

## 3. On the laptop — build

You need an aarch64 cross toolchain (Ubuntu):

```bash
sudo apt install gcc-aarch64-linux-gnu bc bison flex libssl-dev device-tree-compiler
```

```bash
cd ~/linux-imx
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

## 4. Copy onto the SD card (still on the laptop)

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

## 5. On the board — tell U-Boot to use the new DTB

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

## 6. On the board — load driver and capture

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
