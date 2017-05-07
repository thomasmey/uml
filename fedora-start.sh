#!/bin/sh
../linux-um/linux mem=1280m ubd0=/home/thomas/source/uml-images/Fedora.img umid=fedora22 eth0=tuntap,,ee:12:b7:84:00:e0,192.168.4.150 root=/dev/ubda3 plymouth.enable=0 con=pts
