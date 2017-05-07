#!/bin/sh
../linux-um/linux ubd0=Gentoo.img mem=1000M umid=gentoo eth0=tuntap,,ee:13:b8:85:00:f0,192.168.3.1 root=/dev/ubda init=/usr/lib/systemd/systemd

