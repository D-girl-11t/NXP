# Convenience wrapper around the out-of-tree module build in kernel/.
#
# This builds imx519.ko against /lib/modules/$(uname -r)/build, which only
# works where those kernel headers exist — on the board itself, or inside a
# Yocto SDK. For the in-tree build that produces Image + dtbs as well, use
# scripts/install-into-kernel.sh; see docs/build-and-flash.md.

.PHONY: all clean install

all:
	$(MAKE) -C kernel

clean:
	$(MAKE) -C kernel clean

install:
	$(MAKE) -C kernel install
