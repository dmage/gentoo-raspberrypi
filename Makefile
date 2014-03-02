FTP_DISTFILES ?= ftp://mirror.yandex.ru/gentoo-distfiles/
STAGE3_PATH ?= releases/arm/autobuilds/current-stage3-armv6j_hardfp
TIMEZONE ?= Europe/Moscow

CCPREFIX=armv6j-hardfloat-linux-gnueabi-
KERNEL_VERSION=3.6
MAKE_OPTS=-j10

all: boot root

stage3-armv6j_hardfp.tar.bz2:
	wget $(FTP_DISTFILES)/$(STAGE3_PATH)/stage3-armv6j_hardfp-*.tar.bz2 -O $@

firmware-next.tar.gz:
	wget https://github.com/raspberrypi/firmware/archive/next.tar.gz -O $@

root: stage3-armv6j_hardfp.tar.bz2 files/fstab
	mkdir -p ./$@
	sudo tar pxf stage3-armv6j_hardfp.tar.bz2 -C ./$@
	
	sudo cp ./$@/usr/share/zoneinfo/$(TIMEZONE) ./$@/etc/localtime
	echo $(TIMEZONE) | sudo tee ./$@/etc/timezone
	
	cat ./files/fstab | sudo tee ./$@/etc/fstab
	
	sudo sed -e 's#localhost#raspberrypi#g' -i ./$@/etc/conf.d/hostname
	echo 'config_eth0="dhcp"' | sudo tee -a ./$@/etc/conf.d/net
	sudo ln -s net.lo ./$@/etc/init.d/net.eth0
	
	if ! sudo grep "^root:\*:" ./$@/etc/shadow >/dev/null; then \
		HASH=`openssl passwd -1`; \
		sudo sed -e "s#^root:\*:#root:$$HASH:#" -i ./$@/etc/shadow; \
	fi

firmware-next: firmware-next.tar.gz
	tar xf $<
	touch $@

.PHONY: linux/.git/HEAD
linux/.git/HEAD:
	mkdir -p linux
	( \
		cd linux; \
		git init; \
		git fetch git://github.com/raspberrypi/linux.git rpi-$(KERNEL_VERSION).y:refs/remotes/origin/rpi-$(KERNEL_VERSION).y; \
		git checkout origin/rpi-$(KERNEL_VERSION).y; \
		git reset --hard ; git clean --force; \
	)

linux: linux/.git/HEAD
	touch -r $< $@

.PHONY: menuconfig
menuconfig:
	( cd linux; make ARCH=arm menuconfig )

ifdef QEMU

linux/.config: linux files/.config
	( cd linux ; make ARCH=arm mrproper )
	( cd linux ; make ARCH=arm versatile_defconfig )
	sed -i -e 's/^# \(CONFIG_AEABI\) .*$$/\1=y/' linux/.config
	sed -i -e 's/^# \(CONFIG_PCI\) .*$$/\1=y/' linux/.config
	( cd linux ; yes "" | make ARCH=arm oldconfig )

else

linux/.config: linux files/.config
	( cd linux ; make ARCH=arm mrproper )
	cp files/.config linux/
	( cd linux ; make ARCH=arm oldconfig )

endif

linux/arch/arm/boot/Image build/modules: linux linux/.config files/.config
	( \
		cd linux; \
		make ARCH=arm CROSS_COMPILE=$(CCPREFIX) $(MAKE_OPTS); \
		make ARCH=arm CROSS_COMPILE=$(CCPREFIX) $(MAKE_OPTS) modules; \
		make ARCH=arm CROSS_COMPILE=$(CCPREFIX) INSTALL_MOD_PATH=../build/modules modules_install; \
	)
	find build/modules -type l -print -delete
	touch build/modules

boot: firmware-next linux/arch/arm/boot/Image files/cmdline.txt
	mkdir -p ./boot/
	cp ./firmware-next/boot/bootcode.bin ./boot/
	cp ./firmware-next/boot/fixup.dat ./boot/
	cp ./firmware-next/boot/start.elf ./boot/
	cp ./linux/arch/arm/boot/Image ./boot/kernel.img
	cp ./files/cmdline.txt ./boot/
	touch $@

.PHONY: clean
clean:
	rm -rf firmware-next boot build
	cd linux ; rm -rf include fs drivers arch
	sudo rm -rf root

.PHONY: distclean
distclean: clean
	rm -rf linux firmware-next.tar.gz stage3-armv6j_hardfp.tar.bz2
