# Windows laptop + i.MX93 + IMX519

You can do this from Windows. Split it like this:

| On Windows | In WSL2 Ubuntu (required) | On the i.MX93 board |
| --- | --- | --- |
| Serial console (COM port) | Patch linux-imx and **build** kernel/DTB | U-Boot `fdtfile` + capture |
| Copy `Image` / `.dtb` / modules onto the SD card | Cross-compile `aarch64` | `modprobe imx519`, `v4l2-ctl` |

You **cannot** build NXP `linux-imx` in PowerShell or Visual Studio. Use **WSL2**. The board still runs Linux; Windows is only the host.

---

## A. Windows — serial console (PuTTY)

1. Power the i.MX93 from its own supply, then plug the **debug USB** into the PC.
2. Open **Device Manager → Ports (COM & LPT)**.
   - You want a USB serial device: `USB Serial Port (COMx)`, `MCU-LINK`, `USB-Enhanced-SERIAL`, or `USB CDC`.
   - The EVK often shows **several** COM ports. Try the **lowest** number first, then the next.
3. Install [PuTTY](https://www.putty.org/).
4. Session:
   - Connection type: **Serial**
   - Serial line: `COM5` (use **your** COMx)
   - Speed: **115200**
5. Open. Press Enter. You should see `=>` (U-Boot) or a Linux login.

If Device Manager has a yellow bang, install the NXP MCU-Link / MCUXpresso driver, or the FTDI VCP driver, depending on which debug chip your board uses.

**Tera Term** is the same idea: Serial, COMx, 115200 8N1, no flow control.

---

## B. Windows — install WSL2 (one time)

In **PowerShell as Administrator**:

```powershell
wsl --install -d Ubuntu
```

Reboot if Windows asks. Open **Ubuntu** from the Start menu, create a UNIX username/password.

Then in that Ubuntu window:

```bash
sudo apt update
sudo apt install -y git build-essential gcc-aarch64-linux-gnu bc bison flex \
    libssl-dev device-tree-compiler python3
```

Your Windows files are visible inside WSL as `/mnt/c/...`. Prefer keeping the kernel tree **inside WSL** (`~/linux-imx`) — NTFS (`/mnt/c`) is slow and can break kernel builds.

---

## C. WSL — get this project and linux-imx

```bash
cd ~
git clone <this-repo-url> imx519-imx93

# Match the kernel on the board (after it boots: uname -r). Example:
git clone -b lf-6.6.52-2.2.0 https://github.com/nxp-imx/linux-imx.git
```

If you already have an NXP BSP / Yocto checkout on `C:\`, copy it into WSL or clone fresh in `~`.

---

## D. WSL — what to change (this is the driver work)

```bash
cd ~/imx519-imx93
./scripts/install-into-kernel.sh ~/linux-imx
```

That edits **linux-imx inside WSL**, not Windows:

- adds `drivers/media/i2c/imx519.c`
- adds `arch/arm64/boot/dts/freescale/imx93-11x11-evk-imx519.dts`
- enables `CONFIG_VIDEO_IMX519=m` / `CONFIG_VIDEO_AK7375=m` after the merge_config step below

Build:

```bash
cd ~/linux-imx
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

make imx_v8_defconfig
./scripts/kconfig/merge_config.sh -m .config arch/arm64/configs/imx519.config
make olddefconfig
grep -E 'VIDEO_IMX519|VIDEO_AK7375' .config
make -j$(nproc) Image modules dtbs
```

When it finishes you need these files:

```
~/linux-imx/arch/arm64/boot/Image
~/linux-imx/arch/arm64/boot/dts/freescale/imx93-11x11-evk-imx519.dtb
```

Copy them to Windows so Explorer can write the SD card:

```bash
mkdir -p /mnt/c/imx519-out
cp arch/arm64/boot/Image /mnt/c/imx519-out/
cp arch/arm64/boot/dts/freescale/imx93-11x11-evk-imx519.dtb /mnt/c/imx519-out/
# modules: pack the .ko for the running kernel version
find . -name 'imx519.ko' -o -name 'ak7375.ko'
cp drivers/media/i2c/imx519.ko /mnt/c/imx519-out/ || true
```

On Windows that folder is `C:\imx519-out\`.

---

## E. Windows — copy onto the SD card

1. Take the EVK SD card out of the board, insert it in the PC (USB reader).
2. Windows will show a **small FAT partition** (often `BOOT`) and may ignore the Linux ext4 partition (that is normal).

**FAT / BOOT partition** (you can use Explorer):

- Copy `C:\imx519-out\Image` over the existing `Image` (keep a backup).
- Copy `imx93-11x11-evk-imx519.dtb` **next to** `imx93-11x11-evk.dtb`.
- Do **not** delete the old DTB yet.

**ext4 rootfs** (`/lib/modules`, capture scripts): Windows Explorer cannot write ext4.

Options:

1. **WSL** (easiest if the card is `/dev/sdX` inside WSL):

   ```bash
   lsblk
   sudo mkdir -p /mnt/sdboot /mnt/sdroot
   sudo mount /dev/sdX1 /mnt/sdboot     # FAT
   sudo mount /dev/sdX2 /mnt/sdroot     # ext4; number may differ
   sudo cp /mnt/c/imx519-out/Image /mnt/sdboot/
   sudo cp /mnt/c/imx519-out/imx93-11x11-evk-imx519.dtb /mnt/sdboot/
   sudo mkdir -p /mnt/sdroot/home/root/imx519
   sudo cp -a ~/imx519-imx93/scripts /mnt/sdroot/home/root/imx519/
   # install modules into the rootfs
   cd ~/linux-imx
   sudo make ARCH=arm64 INSTALL_MOD_PATH=/mnt/sdroot modules_install
   sudo umount /mnt/sdboot /mnt/sdroot
   ```

   In WSL2, `lsblk` sometimes **does not** see a USB SD reader. If so, use option 2.

2. **Ext2Fsd / DiskGenius / a small Ubuntu live USB**, or copy `imx519.ko` later with `scp` once the board is on Ethernet.

3. After first boot with the **new DTB** but **old modules**, copy the `.ko` over Ethernet:

   ```powershell
   scp C:\imx519-out\imx519.ko root@<board-ip>:/lib/modules/$(uname -r)/
   ```

   On the board you would run that path after `uname -r`. Simpler: from WSL `scp` to the board IP.

Eject the SD card safely, put it back in the board.

---

## F. Board — U-Boot (in PuTTY)

Power on, click inside PuTTY, mash a key to stop at `=>`:

```
setenv fdtfile imx93-11x11-evk-imx519.dtb
saveenv
boot
```

If nothing changes, the image may use a different variable:

```
printenv fdtfile
printenv fdt_file
setenv fdt_file imx93-11x11-evk-imx519.dtb
saveenv
boot
```

FRDM board: use `imx93-11x11-frdm-imx519.dtb` instead.

---

## G. Board — load camera and capture

Still in PuTTY, login (`root`, often no password on NXP images):

```bash
dmesg | grep -i imx519
modprobe imx519
i2cdetect -y 2
```

You must see `1a`. Then:

```bash
cd /home/root/imx519
./scripts/setup-pipeline.sh 1920 1080
./scripts/capture-still.sh shot.raw
./scripts/capture-video.sh 60 clip.raw
```

Copy the `.raw` file to Windows (USB stick, `scp`, or Samba), then in WSL or with Python on Windows:

```bash
python3 userspace/raw10_to_png.py --width 1920 --height 1080 shot.raw shot.png
```

On Windows you can `pip install numpy` and run the same script in PowerShell if Python is installed.

---

## Quick “where do I type this?”

| Step | Window |
| --- | --- |
| `COMx` 115200 | **PuTTY** |
| `install-into-kernel.sh`, `make Image dtbs` | **Ubuntu (WSL)** |
| Copy `Image` + `.dtb` | **Explorer** on the SD FAT partition, or WSL `mount` |
| `setenv fdtfile ...` | **PuTTY** at U-Boot `=>` |
| `modprobe` / capture scripts | **PuTTY** after Linux boots |

---

## If it fails on Windows specifically

| Problem | Fix |
| --- | --- |
| No COM port | Device Manager drivers; try the other USB port labeled Debug / MCU-Link |
| Garbage in PuTTY | Wrong COM port or baud not 115200 |
| `wsl --install` blocked | Enable Virtual Machine Platform in Windows Features |
| Kernel build on `/mnt/c` fails | Clone `linux-imx` under `~/` in WSL, not on `C:` |
| SD card shows only one drive | That is the FAT bootfs; use WSL to mount ext4, or scp `.ko` after boot |
| Still seeing `ap1302` | U-Boot is still loading `imx93-11x11-evk.dtb` — step F |
| `i2cdetect` has no `1a` | Adapter/cable, not Windows |

Hardware limits (1080p max through ISI, RAW not JPEG) are unchanged: see `docs/hardware.md`.
