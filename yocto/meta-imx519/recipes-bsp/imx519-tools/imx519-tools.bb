SUMMARY = "IMX519 capture helpers for i.MX93"
DESCRIPTION = "media-ctl / v4l2-ctl wrappers and a RAW10 demosaic tool for the Arducam IMX519 on NXP i.MX93."
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

SRC_URI = " \
    file://setup-pipeline.sh \
    file://capture-still.sh \
    file://capture-video.sh \
    file://focus.sh \
    file://i2c-probe.sh \
    file://raw10_to_png.py \
    file://imx519_capture.py \
"

S = "${WORKDIR}"

RDEPENDS:${PN} = "v4l-utils bash"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/setup-pipeline.sh ${D}${bindir}/imx519-setup-pipeline
    install -m 0755 ${WORKDIR}/capture-still.sh ${D}${bindir}/imx519-capture-still
    install -m 0755 ${WORKDIR}/capture-video.sh ${D}${bindir}/imx519-capture-video
    install -m 0755 ${WORKDIR}/focus.sh ${D}${bindir}/imx519-focus
    install -m 0755 ${WORKDIR}/i2c-probe.sh ${D}${bindir}/imx519-i2c-probe
    install -m 0755 ${WORKDIR}/raw10_to_png.py ${D}${bindir}/imx519-raw10-to-png
    install -m 0755 ${WORKDIR}/imx519_capture.py ${D}${bindir}/imx519-capture
}

FILES:${PN} = "${bindir}/*"
