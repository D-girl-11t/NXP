# Yocto helpers for the IMX519 i.MX93 port.
#
# 1. Copy (or symlink) this meta-imx519 directory into your build sources.
# 2. Place the driver/DTS/scripts next to the recipes (done by scripts/sync-yocto.sh).
# 3. In conf/bblayers.conf add:
#      BBLAYERS += "/path/to/meta-imx519"
# 4. In conf/local.conf add:
#      IMAGE_INSTALL:append = " imx519-tools"
#      KERNEL_DEVICETREE:append = " freescale/imx93-11x11-evk-imx519.dtb"
# 5. bitbake linux-imx imx519-tools
#
# Boot the board with:
#   setenv fdtfile imx93-11x11-evk-imx519.dtb
#   saveenv
#   boot
