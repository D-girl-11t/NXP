# Doing the host side from Windows

You can run this project from a Windows PC, but you **cannot** build NXP's
`linux-imx` in PowerShell or Visual Studio. Use **WSL2** for the build and
Windows only for the serial console and for writing the SD card.

| On Windows | In WSL2 Ubuntu | On the board |
| --- | --- | --- |
| Serial console on a COM port | Patch `linux-imx`, cross-compile kernel, dtb and module | U-Boot `fdtfile`, `modprobe`, capture |
| Copy `Image` and `.dtb` to the FAT partition | Everything in [build-and-flash.md](build-and-flash.md) | |

This document covers only the Windows-specific parts. The actual build and
install steps are in [build-and-flash.md](build-and-flash.md) and apply
unchanged inside WSL.

## 1. Serial console with PuTTY

1. Power the board from its own supply, then plug the **debug USB** into the
   PC.
2. Open **Device Manager → Ports (COM & LPT)**. Look for `USB Serial Port
   (COMx)`, `MCU-LINK`, `USB-Enhanced-SERIAL` or `USB CDC`. NXP boards often
   expose several COM ports — try the lowest number first, then the next.
3. Install [PuTTY](https://www.putty.org/).
4. Connection type **Serial**, serial line `COMx` (yours, not literally
   `COM5`), speed **115200**.
5. Open and press Enter. You should see `=>` from U-Boot or a Linux login.

A yellow warning triangle in Device Manager means a missing driver — install
the NXP MCU-Link / MCUXpresso driver, or the FTDI VCP driver, depending on
which debug chip your board has.

Tera Term works the same way: Serial, COMx, 115200 8N1, no flow control.

## 2. Install WSL2

In **PowerShell as Administrator**:

```powershell
wsl --install -d Ubuntu
```

Reboot if prompted, then open **Ubuntu** from the Start menu and create a
UNIX user. Inside that shell:

```bash
sudo apt update
sudo apt install -y git build-essential gcc-aarch64-linux-gnu bc bison flex \
    libssl-dev device-tree-compiler python3
```

Your Windows drives appear as `/mnt/c/...`, but **keep the kernel tree inside
WSL** (`~/linux-imx`). NTFS through `/mnt/c` is slow and breaks kernel builds
on file-permission and case-sensitivity issues.

## 3. Build inside WSL

Follow [build-and-flash.md](build-and-flash.md) from section 3 onwards,
verbatim. Nothing about it is Linux-host-specific once you are inside WSL.

When the build finishes, copy the artefacts somewhere Explorer can see:

```bash
mkdir -p /mnt/c/imx519-out
cd ~/linux-imx
cp arch/arm64/boot/Image /mnt/c/imx519-out/
cp arch/arm64/boot/dts/freescale/imx93-11x11-frdm-imx519.dtb /mnt/c/imx519-out/
cp drivers/media/i2c/imx519.ko drivers/media/i2c/ak7375.ko /mnt/c/imx519-out/
```

That is `C:\imx519-out\` in Explorer.

## 4. Write the SD card

Put the card in the PC. Windows shows the **small FAT partition** and
ignores the Linux ext4 one — that is normal.

**FAT partition**, in Explorer:

- Back up the existing `Image`, then copy `C:\imx519-out\Image` over it.
- Copy `imx93-11x11-frdm-imx519.dtb` next to the stock dtb.
- Do not delete the stock dtb.

**ext4 rootfs** — Explorer cannot write it, so you need one of:

1. **WSL**, if the reader shows up as a block device:

   ```bash
   lsblk
   sudo mkdir -p /mnt/sdboot /mnt/sdroot
   sudo mount /dev/sdX1 /mnt/sdboot     # FAT
   sudo mount /dev/sdX2 /mnt/sdroot     # ext4
   cd ~/linux-imx
   sudo make ARCH=arm64 INSTALL_MOD_PATH=/mnt/sdroot modules_install
   sudo mkdir -p /mnt/sdroot/home/root
   sudo cp -a ~/imx519-nxp-link /mnt/sdroot/home/root/imx519
   sudo umount /mnt/sdboot /mnt/sdroot
   ```

   WSL2 often does **not** see a USB SD reader through `lsblk`. If so, use
   one of the next two options.

2. A third-party ext4 driver (Ext2Fsd, DiskGenius) or a small Ubuntu live
   USB.

3. Boot with the **new dtb** and the old modules first, then copy the module
   over Ethernet once the board is up. This is usually the least painful:

   ```powershell
   scp C:\imx519-out\imx519.ko root@<board-ip>:/tmp/
   ```

   Remember that the module must match the `Image` you installed — see
   [the ABI section](build-and-flash.md#5-choose-a-kernel-config).

Eject the card safely and return it to the board.

## 5. U-Boot and capture

Both happen in PuTTY, exactly as in
[build-and-flash.md](build-and-flash.md#8-point-u-boot-at-the-new-device-tree)
and [capture.md](capture.md).

To convert a capture on Windows, either use WSL or install Python plus
`numpy` natively and run the same script:

```powershell
python userspace\raw10_to_png.py --width 1920 --height 1080 shot.raw shot.png
```

## Where do I type this?

| Step | Window |
| --- | --- |
| `COMx` at 115200 | **PuTTY** |
| `install-into-kernel.sh`, `make Image modules dtbs` | **Ubuntu (WSL)** |
| Copying `Image` and `.dtb` | **Explorer** on the FAT partition, or WSL `mount` |
| `setenv fdtfile ...` | **PuTTY**, at the U-Boot `=>` prompt |
| `modprobe`, capture scripts | **PuTTY**, after Linux boots |

## Windows-specific failures

| Problem | Fix |
| --- | --- |
| No COM port appears | Install the debug-probe driver; try the other USB port marked Debug or MCU-Link |
| Garbage characters in PuTTY | Wrong COM port, or baud is not 115200 |
| `wsl --install` is blocked | Enable **Virtual Machine Platform** in Windows Features |
| Kernel build fails under `/mnt/c` | Clone `linux-imx` under `~/` inside WSL, not on `C:` |
| SD card shows only one drive | That is the FAT boot partition; ext4 needs WSL or a third-party driver |

Everything else — ISI limits, RAW instead of JPEG, the module ABI — is not
Windows-related. See [troubleshooting.md](troubleshooting.md).
