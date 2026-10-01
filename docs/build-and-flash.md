# Build and install walkthrough

The full path from a clean host to a camera that probes on the board. Work
happens in two places:

| Where | What you do |
| --- | --- |
| **Host** (Linux laptop, or WSL2 — see [windows.md](windows.md)) | Patch `linux-imx`, cross-compile the kernel, device tree and module |
| **Board** | Point U-Boot at the new device tree, load the module, capture |

You never edit the Raspberry Pi `imx519.c`. You copy the ported driver from
this repository into NXP's kernel tree.

## 1. Connect the hardware

1. **Power** the board from its own supply, not only the debug USB.
2. **Debug UART** to the host. On NXP i.MX93 boards this is usually
   `/dev/ttyUSB0` or `/dev/ttyACM0` at **115200 8N1**. This is how you see
   U-Boot.
3. **Ethernet**, so you can `scp` files after the first boot. Optional if you
   plan to move everything on the SD card.
4. **Camera**: Arducam IMX519 → Raspberry-Pi-to-NXP camera adapter → the CSI
   connector. The board's CSI socket is not a Raspberry Pi camera socket, so
   the adapter is not optional. On FRDM-i.MX93 the camera goes on **P6**, the
   MIPI CSI connector; see [hardware.md](hardware.md#connectors).

Power off while seating the camera cable.

## 2. Open a serial console

```bash
sudo apt install picocom
sudo picocom -b 115200 /dev/ttyUSB0
```

If that port is busy, try `/dev/ttyACM0`. Press Enter — you should get `=>`
from U-Boot or a Linux login prompt.

## 3. Get the two source trees

You need **two directories** on the host, and they are easy to confuse.

| Directory | What it is |
| --- | --- |
| this repository | the IMX519 driver, device trees, scripts and docs |
| `linux-imx` | NXP's kernel, the one the board actually boots |

`linux-imx` is **not** the Raspberry Pi kernel and not Arducam's GitHub. The
board cannot boot this repository on its own; the install script copies files
into `linux-imx` so the next `make` includes the camera.

Find out which kernel the board runs:

```bash
uname -r
```

Then clone NXP's kernel at the matching tag. For `6.18.2-1.0.0-g*`:

```bash
cd ~
git clone -b lf-6.18.2-1.0.0 https://github.com/nxp-imx/linux-imx.git
```

For a `6.6.x` board you want `lf-6.6.y` instead. Getting this wrong is the
root of most later failures.

If you already have a Yocto BSP, its kernel source is already on disk —
something like
`~/imx-yocto-bsp/tmp/work-shared/imx93-11x11-lpddr4x-frdm/kernel-source`.
Use that; do not clone a second copy. It is the right directory if
`ls <dir>/drivers/media/i2c` works.

Install the cross toolchain:

```bash
sudo apt install -y gcc-aarch64-linux-gnu bc bison flex libssl-dev \
    device-tree-compiler
```

## 4. Install the driver into `linux-imx`

```bash
cd /path/to/this/repo
./scripts/install-into-kernel.sh ~/linux-imx
```

You should see copy messages for `imx519.c` and the device trees. Nothing is
installed on the board yet.

What changes inside `linux-imx`:

| File | Change |
| --- | --- |
| `drivers/media/i2c/imx519.c` | the sensor driver |
| `drivers/media/i2c/Kconfig.imx519` | `CONFIG_VIDEO_IMX519` |
| `drivers/media/i2c/Kconfig` | sources the above |
| `drivers/media/i2c/Makefile` | builds `imx519.o` |
| `arch/arm64/boot/dts/freescale/imx93-11x11-frdm-imx519.dts` | FRDM board tree |
| `arch/arm64/boot/dts/freescale/Makefile` | builds the new dtbs |
| `arch/arm64/configs/imx519.config` | the config fragment |

`dts/` also contains device trees for the 11x11 EVK. They are reference
copies and have never been tested on hardware; the script only installs one
if the kernel tree has a matching EVK board file, and it removes any dtb
target that cannot build so `make dtbs` does not abort on an unused file.

## 5. Choose a kernel config

Read this before building — it decides whether your module will load at all.
There are two routes.

### Route A — replace the kernel (simplest, what we did)

Build `Image`, modules and dtbs from a defconfig, and install **all three**
on the board. The running kernel then matches the module by construction.

```bash
cd ~/linux-imx
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make imx_v8_defconfig
./scripts/kconfig/merge_config.sh -m .config arch/arm64/configs/imx519.config
make olddefconfig
grep -E 'VIDEO_IMX519|VIDEO_AK7375' .config
# CONFIG_VIDEO_IMX519=m
# CONFIG_VIDEO_AK7375=m
make -j"$(nproc)" Image modules dtbs
```

### Route B — keep the BSP kernel

If you want to keep the stock BSP `Image`, you must build against the
board's own configuration, or the module will be rejected with
`disagrees about version of symbol`. Start from the running config:

```bash
# on the board
zcat /proc/config.gz > /tmp/running.config
```

Copy that file to the host as `~/running.config` — the path must be real,
not a placeholder — then:

```bash
cd ~/linux-imx
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
cp ~/running.config .config
./scripts/kconfig/merge_config.sh -m .config arch/arm64/configs/imx519.config
make olddefconfig
grep -E 'VIDEO_IMX519|VIDEO_AK7375|LOCALVERSION' .config
make -j"$(nproc)" Image modules dtbs
```

[`scripts/rebuild-image-from-running-config.sh`](../scripts/rebuild-image-from-running-config.sh)
does the same thing in one command.

If `~/running.config` does not exist, `merge_config.sh` silently keeps
whatever `.config` was already there and you end up on route A without
realising it — check `grep LOCALVERSION .config`. If `/proc/config.gz` is
missing entirely, the BSP was built without `CONFIG_IKCONFIG_PROC` and you
need the `.config` from the Yocto build that produced the running kernel.

Even on route B, the module only loads if the resulting `vermagic` matches.
Verify on the board with
[`scripts/check-ko-abi.sh`](../scripts/check-ko-abi.sh) before blaming the
hardware.

### Building on the board instead

If `/lib/modules/$(uname -r)/build` exists, the board has kernel headers and
you can skip all of this:

```bash
./scripts/build-module-on-target.sh
```

NXP's prebuilt demo images do not ship that directory.

## 6. Outputs

```
~/linux-imx/arch/arm64/boot/Image
~/linux-imx/arch/arm64/boot/dts/freescale/imx93-11x11-frdm-imx519.dtb
~/linux-imx/drivers/media/i2c/imx519.ko
~/linux-imx/drivers/media/i2c/ak7375.ko
```

Also note the kernel version string you just built — you will need it for
the module path:

```bash
make -s kernelrelease
```

## 7. Move the files to the board

Either route works. Pick one.

### Via the SD card

```bash
# adjust /dev/sdX and the partition numbers to your reader
sudo mkdir -p /mnt/boot /mnt/root
sudo mount /dev/sdX1 /mnt/boot      # FAT: Image and *.dtb
sudo mount /dev/sdX2 /mnt/root      # ext4: rootfs

sudo cp /mnt/boot/Image /mnt/boot/Image.stock          # rescue copy first
sudo cp arch/arm64/boot/Image /mnt/boot/
sudo cp arch/arm64/boot/dts/freescale/imx93-11x11-frdm-imx519.dtb /mnt/boot/
sudo make ARCH=arm64 INSTALL_MOD_PATH=/mnt/root modules_install

sudo mkdir -p /mnt/root/home/root
sudo cp -a /path/to/this/repo /mnt/root/home/root/imx519

sudo umount /mnt/boot /mnt/root
```

### Over Ethernet

A direct cable between host and board has no DHCP server, so `udhcpc` will
broadcast discover packets forever. Assign static addresses on both ends:

```bash
# host
sudo ip addr add 192.168.50.1/24 dev eno1
sudo ip link set eno1 up

# board
ip link set eth0 up
ip addr add 192.168.50.2/24 dev eth0
```

Confirm with `ping -c3 192.168.50.1` from the board. This does not survive a
reboot — re-apply it, or install a `systemd-networkd` file for persistence.
If `scp` later reports `No route to host`, the address was lost on reboot.

Then:

```bash
# host
tar czf ~/imx519-mods.tar.gz -C <modules staging dir> .
scp arch/arm64/boot/Image root@192.168.50.2:/tmp/
scp ~/imx519-mods.tar.gz root@192.168.50.2:/tmp/
scp arch/arm64/boot/dts/freescale/imx93-11x11-frdm-imx519.dtb \
    root@192.168.50.2:/tmp/

# board — the FAT boot partition is usually mounted here
tar xzf /tmp/imx519-mods.tar.gz -C /lib/modules/
cp /run/media/boot-mmcblk0p1/Image /run/media/boot-mmcblk0p1/Image.stock
cp /tmp/Image /run/media/boot-mmcblk0p1/Image
cp /tmp/imx93-11x11-frdm-imx519.dtb /run/media/boot-mmcblk0p1/
sync
```

**Keep `Image.stock`.** If a new kernel fails to boot, U-Boot can only load
a rescue image from the FAT partition, not from the rootfs.

## 8. Point U-Boot at the new device tree

Reboot and press a key to stop at the `=>` prompt:

```
setenv fdtfile imx93-11x11-frdm-imx519.dtb
saveenv
boot
```

Some NXP images use `fdt_file` instead:

```
printenv fdtfile fdt_file
setenv fdt_file imx93-11x11-frdm-imx519.dtb
saveenv
```

`setenv` typed inside Linux does nothing — it must be at the U-Boot prompt,
or via `fw_setenv` if that tool is installed. If you cannot reach U-Boot at
all, the fallback is to **overwrite the filename U-Boot already loads**:

```bash
cp /run/media/boot-mmcblk0p1/imx93-11x11-frdm.dtb \
   /run/media/boot-mmcblk0p1/imx93-11x11-frdm.dtb.orig
cp /tmp/imx93-11x11-frdm-imx519.dtb \
   /run/media/boot-mmcblk0p1/imx93-11x11-frdm.dtb
sync && reboot
```

The dtb must live in the same directory U-Boot already loads the stock one
from, normally the FAT boot partition.

## 9. Verify

```bash
uname -r                                 # matches `make -s kernelrelease`
cat /proc/device-tree/model              # "... with Arducam IMX519"
depmod -a
modprobe imx519
modprobe ak7375
dmesg | grep -i imx519
ls /sys/bus/i2c/drivers/imx519/          # 2-001a here means bound
./scripts/i2c-probe.sh 2
```

A clean result is: the model string mentions the IMX519, `modprobe` prints no
symbol errors, `2-001a` appears under the driver, and nothing relevant is
listed in `/sys/kernel/debug/devices_deferred`.

Anything else, start at [troubleshooting.md](troubleshooting.md).

## 10. Capture

Continue with [capture.md](capture.md).
