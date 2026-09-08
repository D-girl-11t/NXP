.PHONY: all clean install

all:
	$(MAKE) -C kernel

clean:
	$(MAKE) -C kernel clean

install:
	$(MAKE) -C kernel install
