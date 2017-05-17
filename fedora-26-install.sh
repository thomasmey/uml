#!/bin/sh
#../linux/linux mem=1280m ubd0=/home/thomas/source/uml-images/Fedora.img umid=fedora22 eth0=tuntap,,ee:12:b7:84:00:e0,192.168.4.150 root=/dev/ubda3 plymouth.enable=0 con=pts
../linux/linux mem=1280m ubd0=Fedora-26.img ubd1=/home/thomas/Downloads/Fedora-Server-netinst-x86_64-26-Alpha-1.7.iso umid=fedora26 initrd=initrd.img inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-26 quiet
