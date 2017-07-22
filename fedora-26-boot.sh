#!/bin/sh

# x86_64 or i386
SUBARCH=x86_64

LINUX_DIR=/home/thomas/git/linux

cp config-$SUBARCH $LINUX_DIR/.config
make ARCH=um -C $LINUX_DIR/ -j$(nproc)
$LINUX_DIR/linux mem=1280m umid=fedora26 ubd0=fedora26-x86_64-root.img ubd1=fedora26-x86_64-boot.img root=/dev/mapper/fedora-root ro rd.lvm.lv=fedora/root rd.lvm.lv=fedora/swap rhgb quiet LANG=de_DE.UTF-8 initrd=initramfs-4.11.2-300.fc26.x86_64.img plymouth.enable=0
