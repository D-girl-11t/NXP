FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " \
    file://imx519.c \
    file://Kconfig.imx519 \
    file://imx519.cfg \
    file://imx93-11x11-evk-imx519.dts \
    file://imx93-11x11-frdm-imx519.dts \
"

do_configure:prepend() {
    install -m 0644 ${WORKDIR}/imx519.c ${S}/drivers/media/i2c/imx519.c
    install -m 0644 ${WORKDIR}/Kconfig.imx519 ${S}/drivers/media/i2c/Kconfig.imx519

    if ! grep -q 'Kconfig.imx519' ${S}/drivers/media/i2c/Kconfig; then
        echo 'source "drivers/media/i2c/Kconfig.imx519"' >> ${S}/drivers/media/i2c/Kconfig
    fi
    if ! grep -q 'imx519.o' ${S}/drivers/media/i2c/Makefile; then
        echo 'obj-$(CONFIG_VIDEO_IMX519) += imx519.o' >> ${S}/drivers/media/i2c/Makefile
    fi

    install -m 0644 ${WORKDIR}/imx93-11x11-evk-imx519.dts \
        ${S}/arch/arm64/boot/dts/freescale/imx93-11x11-evk-imx519.dts
    if ! grep -q 'imx93-11x11-evk-imx519.dtb' ${S}/arch/arm64/boot/dts/freescale/Makefile; then
        echo 'dtb-$(CONFIG_ARCH_MXC) += imx93-11x11-evk-imx519.dtb' \
            >> ${S}/arch/arm64/boot/dts/freescale/Makefile
    fi

    if [ -f ${WORKDIR}/imx93-11x11-frdm-imx519.dts ]; then
        install -m 0644 ${WORKDIR}/imx93-11x11-frdm-imx519.dts \
            ${S}/arch/arm64/boot/dts/freescale/imx93-11x11-frdm-imx519.dts
        if ! grep -q 'imx93-11x11-frdm-imx519.dtb' ${S}/arch/arm64/boot/dts/freescale/Makefile; then
            echo 'dtb-$(CONFIG_ARCH_MXC) += imx93-11x11-frdm-imx519.dtb' \
                >> ${S}/arch/arm64/boot/dts/freescale/Makefile
        fi
    fi
}

# NXP linux-imx merges fragments listed here on top of imx_v8_defconfig.
DELTA_KERNEL_DEFCONFIG:append = " imx519.cfg"
