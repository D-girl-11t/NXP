# Out-of-tree build for the IMX519 sensor on NXP linux-imx.
#
# On the board (or in a Yocto SDK):
#   make -C /lib/modules/$(uname -r)/build M=$PWD modules
#   sudo make -C /lib/modules/$(uname -r)/build M=$PWD modules_install
#   sudo depmod -a
#   sudo modprobe imx519

obj-m += imx519.o

KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build
PWD       := $(shell pwd)

all:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) modules

clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) clean

install:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) modules_install
	depmod -a
