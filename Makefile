
CROSS_COMPILE=riscv64-linux-musl-
OPENSBI_CROSS_COMPILE=riscv64-unknown-linux-gnu-
LINUX_IMG=linux-xlnx/arch/riscv/boot/Image
OPENSBI_DIR = ../opensbi
PLATFORM = axu15eg
OPENSBI_OBJMK = $(OPENSBI_DIR)/platform/$(PLATFORM)/objects.mk
FW_PAYLOAD = $(OPENSBI_DIR)/build/platform/$(PLATFORM)/firmware/fw_payload.bin
DTB=rocket-chip.dtb
ROOTFS_DIR = rootfs
PWD=$(shell pwd)
QEMU=../taic-qemu/build/qemu-system-riscv64
QEMU_DTB=qemu-riscv-taic.dtb

clean:
	cd busybox && make clean
	cd linux-xlnx && make mrproper

buildfs:
	cd busybox && cp ../.busyboxconfig .config && make ARCH=riscv CROSS_COMPILE=riscv64-linux-musl- && make install ARCH=riscv CROSS_COMPILE=riscv64-linux-musl- CONFIG_PREFIX=../rootfs
	cd $(ROOTFS_DIR) && rm -rf dev var proc tmp home root mnt sys
	cd $(ROOTFS_DIR) && mkdir dev var proc tmp home root mnt sys
	cd $(ROOTFS_DIR)/dev && sudo mknod console c 5 1 && sudo mknod null c 1 3
	cd $(ROOTFS_DIR) && find . | cpio -o --format=newc > ../rootfs.cpio

linux: $(ROOTFS)
	cd linux-xlnx && cp ../.linuxconfig .config && make ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE) -j8
	cp $(LINUX_IMG) .

dts:
	dtc -I dts -O dtb rocket-chip.dts -o $(DTB)

opensbi: $(LINUX_IMG) dts
	sed -i "/FW_PAYLOAD_PATH=/d" $(OPENSBI_OBJMK)
	sed -i "/FW_FDT_PATH=/d" $(OPENSBI_OBJMK)
	sed -i "/FW_PAYLOAD_FDT_ADDR=/d" $(OPENSBI_OBJMK)
	@echo "FW_FDT_PATH=$(PWD)/$(DTB)" >> $(OPENSBI_OBJMK)
	@echo "FW_PAYLOAD_PATH=$(PWD)/Image" >> $(OPENSBI_OBJMK)
	@echo "FW_PAYLOAD_FDT_ADDR=0x82200000" >> $(OPENSBI_OBJMK)
	make -C $(OPENSBI_DIR) PLATFORM=$(PLATFORM) CROSS_COMPILE=$(OPENSBI_CROSS_COMPILE)
	@sed -i "/FW_PAYLOAD_PATH=/d" $(OPENSBI_OBJMK)
	@sed -i "/FW_FDT_PATH=/d" $(OPENSBI_OBJMK)

qemu: $(FW_PAYLOAD)
	make -C $(OPENSBI_DIR) PLATFORM=generic CROSS_COMPILE=$(OPENSBI_CROSS_COMPILE)
	dtc -I dts -O dtb qemu-riscv-taic.dts -o $(QEMU_DTB)
	$(QEMU) -M virt -m 128M -smp 8 -machine virt -nographic -bios $(OPENSBI_DIR)/build/platform/generic/firmware/fw_jump.bin -kernel $(PWD)/Image -dtb $(QEMU_DTB)
upload:
	make linux
	make opensbi
	scp $(FW_PAYLOAD) axu15eg:~