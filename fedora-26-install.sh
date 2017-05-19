#!/bin/sh
LINUX_DIR=/home/thomas/source/linux-um
ISO_FILE=Fedora-Server-netinst-x86_64-26-Alpha-1.7.iso
INITRD=fedora26-initrd.cpio.xz
DISK=Fedora26.img

if [ ! -f "$ISO_FILE" ]; then
   curl -OL "https://download.fedoraproject.org/pub/fedora/linux/releases/test/26_Alpha/Server/x86_64/iso/Fedora-Server-netinst-x86_64-26-Alpha-1.7.iso" 
fi

cp config $LINUX_DIR/.config
make ARCH=um -C $LINUX_DIR/ -j$(nproc)

if [ ! -f "$INITRD" ]; then
   iso-read -i $ISO_FILE -e isolinux/initrd.img --output-file $INITRD
fi

if [ ! -f "$DISK" ]; then
   truncate -s 2G $DISK
fi

$LINUX_DIR/linux mem=1280m ubd0=$DISK ubd1=$ISO_FILE umid=fedora26 initrd=$INITRD inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-26 plymouth.enable=0 eth0=tuntap,,,192.168.5.1 ip=192.168.5.2::192.168.0.1:255.255.255.0:fry:eth0:none nameserver=192.168.0.1


