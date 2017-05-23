#!/bin/sh

# x86_64 or i386
SUBARCH=x86_64

LINUX_DIR=/home/thomas/git/linux
ISO_FILE=Fedora-Server-netinst-$SUBARCH-26-Alpha-1.7.iso
INITRD=fedora26-$SUBARCH-initrd.cpio.xz
DISK=fedora26-$SUBARCH.img

if [ ! -f "$ISO_FILE" ]; then
   curl -OL "https://download.fedoraproject.org/pub/fedora/linux/releases/test/26_Alpha/Server/$SUBARCH/iso/$ISO_FILE" 
fi

cp config-$SUBARCH $LINUX_DIR/.config
make ARCH=um -C $LINUX_DIR/ -j$(nproc)

if [ ! -f "$INITRD" ]; then
   iso-read -i $ISO_FILE -e isolinux/initrd.img --output-file $INITRD
fi

if [ ! -f "$DISK" ]; then
   truncate -s 5G $DISK
fi

# firewall-cmd --zone=home --add-interface=tap0
# firewall-cmd --zone=external --change-interface=wlan0
# sysctl -w vm.max_map_count=265535

$LINUX_DIR/linux mem=1280m ubd0=$DISK ubd1=$ISO_FILE umid=fedora26 initrd=$INITRD inst.stage2=hd:LABEL=Fedora-S-dvd-$SUBARCH-26 plymouth.enable=0 eth0=tuntap,,,192.168.5.1 ip=192.168.5.2::192.168.5.1:255.255.255.0:fry:eth0:none nameserver=192.168.0.1

