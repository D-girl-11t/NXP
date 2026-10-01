# Building with Yocto

[`yocto/meta-imx519`](../yocto/meta-imx519) packages everything in this
repository as a Yocto layer, so the driver, device trees and capture tools
end up in a BSP image instead of being copied onto a running board by hand.

Use this route if you already build your own image with the
[i.MX Yocto Project](https://www.nxp.com/docs/en/user-guide/IMX_YOCTO_PROJECT_USERS_GUIDE.pdf).
It also sidesteps the kernel ABI problem entirely, because bitbake builds the
module and the kernel from the same configuration.

## What the layer contains

| Recipe | Does |
| --- | --- |
| `recipes-kernel/linux/linux-imx_%.bbappend` | Installs `imx519.c`, the Kconfig, both device trees and the config fragment into the kernel source, patches the two Makefiles, and appends `imx519.cfg` to `DELTA_KERNEL_DEFCONFIG` |
| `recipes-bsp/imx519-tools/imx519-tools.bb` | Installs the capture scripts and Python tools into `${bindir}` with an `imx519-` prefix |

The bbappend is a `do_configure:prepend`, so it runs before the kernel's
configure step and the new `CONFIG_VIDEO_IMX519` is picked up by the
defconfig merge.

## Set up

The layer's recipe directories need copies of the sources, which bitbake
fetches with `file://`. Populate them from the canonical copies in this
repository rather than editing two sets of files:

```bash
./scripts/sync-yocto.sh
```

Re-run that after any change to `kernel/imx519.c`, the device trees, or the
scripts.

Then copy or symlink `yocto/meta-imx519` into your build's layer directory
and register it in `conf/bblayers.conf`:

```
BBLAYERS += "/path/to/meta-imx519"
```

In `conf/local.conf`:

```
IMAGE_INSTALL:append = " imx519-tools"
KERNEL_DEVICETREE:append = " freescale/imx93-11x11-frdm-imx519.dtb"
```

## Build

```bash
bitbake linux-imx imx519-tools
# or rebuild the whole image
bitbake imx-image-multimedia
```

Check that the config fragment actually took effect:

```bash
bitbake -e linux-imx | grep ^DELTA_KERNEL_DEFCONFIG=
grep VIDEO_IMX519 tmp/work/*/linux-imx/*/build/.config
```

## Boot

```
setenv fdtfile imx93-11x11-frdm-imx519.dtb
saveenv
boot
```

## On the board

The tools are on `PATH` with an `imx519-` prefix instead of being run from a
checkout:

```bash
imx519-i2c-probe 2
imx519-setup-pipeline 1920 1080
imx519-capture-still shot.raw
imx519-focus 512
imx519-raw10-to-png --width 1920 --height 1080 shot.raw shot.png
```

Everything else is the same as [capture.md](capture.md).

## Compatibility

`LAYERSERIES_COMPAT_imx519` currently lists `kirkstone`, `mickledore`,
`nanbield` and `scarthgap`. Add your release to
[`conf/layer.conf`](../yocto/meta-imx519/conf/layer.conf) if bitbake refuses
the layer.
