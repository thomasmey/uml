#!/bin/sh
LINUX_DIR=/home/thomas/source/linux-um
ISO_FILE=Fedora-Workstation-Live-x86_64-26_Alpha-1.7.iso
INITRD=fedora26-initrd.cpio.xz
DISK=Fedora26.img

if [ ! -f "$ISO_FILE" ]; then
   curl -OL "https://download.fedoraproject.org/pub/fedora/linux/releases/test/26_Alpha/Workstation/x86_64/iso/$ISO_FILE" 
fi

cp config $LINUX_DIR/.config
#make ARCH=um -C $LINUX_DIR/ -j$(nproc)

if [ ! -f "$INITRD" ]; then
   iso-read -i $ISO_FILE -e isolinux/initrd.img --output-file $INITRD
fi

if [ ! -f "$DISK" ]; then
   truncate -s 2G $DISK
fi

$LINUX_DIR/linux mem=1280m ubd0=$DISK ubd1=$ISO_FILE umid=fedora26 initrd=$INITRD root=live:CDLABEL=Fedora-WS-Live-26_A-1-7 rd.live.image plymouth.enable=0 debug
 
