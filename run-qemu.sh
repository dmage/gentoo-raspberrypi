#!/bin/sh
exec qemu-system-arm -kernel ./linux/arch/arm/boot/zImage -m 256 -M versatilepb -serial stdio
