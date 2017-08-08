#!/bin/sh

export ARCH=um
# x86_64 or i386
export SUBARCH=x86_64

LINUX_DIR=~/git/linux

RAW_FILE=Fedora-Cloud-Base-26-1.5.x86_64.raw
CLOUD_INIT_FILE=Fedora-Cloud-Base-Init.iso
KSELFTEST_FILE=Fedora-Cloud-Base-kselftests.img
MODULES_FILE=Fedora-Cloud-Base-modules.img
#INITRD_DIR=`mktemp -d`
INITRD_DIR=`pwd`/initrd

if [ ! -d "$LINUX_DIR" ]; then
  mkdir -p $LINUX_DIR
  git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git $LINUX_DIR
fi

if [ ! -f "$RAW_FILE" ]; then
  curl -OL "https://download.fedoraproject.org/pub/fedora/linux/releases/26/CloudImages/x86_64/images/$RAW_FILE.xz"
  unxz $RAW_FILE.xz
fi

if [ ! -f "$CLOUD_INIT_FILE" ]; then
  TEMP_DIR=`mktemp -d`
  { echo instance-id: iid-local01; echo local-hostname: cloudimg; } > $TEMP_DIR/meta-data
  cat > $TEMPDIR/user-data << EOF
#cloud-config
password: passw0rd
chpasswd: { expire: False }
ssh_pwauth: True

mounts:
 - [ /dev/ubdc, /opt ]

write_files:
 - content: |
     [Unit]
     Description=/etc/rc.d/rc.local Compatibility
     [Install]
     WantedBy=multi-user.target
     [Service]
     Type=simple
     ExecStart=/bin/sh /opt/run_kselftest.sh
     TimeoutSec=0
     RemainAfterExit=yes
     GuessMainPID=no
     WorkingDirectory=/opt/
     StandardOutput=journal+console
   path: /etc/systemd/system/kselftest.service
   permissions: '0755'

runcmd:
  - [ systemctl, daemon-reload ]
  - [ systemctl, enable, kselftest.service ]
  - [ systemctl, start, --no-block, kselftest.service ]

EOF

  ## create a disk to attach with some user-data and meta-data
  genisoimage -output $CLOUD_INIT_FILE -volid cidata -joliet -rock $TEMP_DIR/user-data $TEMP_DIR/meta-data
  rm -R $TEMP_DIR
fi

# crete config
make -C $LINUX_DIR -j$(nproc) allmodconfig

# be less verbose
sed -i 's/CONFIG_GCC_PLUGIN_CYC_COMPLEXITY=y/CONFIG_GCC_PLUGIN_CYC_COMPLEXITY=n/' $LINUX_DIR/.config

# Fedora doesn't have this package available
sed -i 's/CONFIG_UML_NET_VDE=y/CONFIG_UML_NET_VDE=n/' $LINUX_DIR/.config
# pcap is broken
sed -i 's/CONFIG_UML_NET_PCAP=y/CONFIG_UML_NET_PCAP=n/' $LINUX_DIR/.config

# link dynamic
sed -i 's/CONFIG_STATIC_LINK=y/CONFIG_STATIC_LINK=n/' $LINUX_DIR/.config

# either GCOV or KCOV,KCOV_KERNEL, both doesn't seem to work
sed -i 's/CONFIG_GCOV_KERNEL=y/CONFIG_GCOV_KERNEL=n/' $LINUX_DIR/.config
sed -i 's/CONFIG_KCOV=y/CONFIG_KCOV=n/' $LINUX_DIR/.config

# gcov fails the module build with errors like those:
#ERROR: "__gcov_merge_add" [arch/um/drivers/harddog.ko] undefined!
#ERROR: "__gcov_init" [arch/um/drivers/harddog.ko] undefined!
#ERROR: "__gcov_exit" [arch/um/drivers/harddog.ko] undefined!
sed -i 's/CONFIG_GCOV=y/CONFIG_GCOV=n/' $LINUX_DIR/.config

# this fails
sed -i 's/CONFIG_OF_UNITTEST=y/CONFIG_OF_UNITTEST=n/' $LINUX_DIR/.config

# increase stack size
sed -i 's/CONFIG_KERNEL_STACK_ORDER=./CONFIG_KERNEL_STACK_ORDER=3/' $LINUX_DIR/.config

# we need ext4
sed -i 's/CONFIG_EXT4_FS=./CONFIG_EXT4_FS=y/' $LINUX_DIR/.config
#sed -i 's/CONFIG_ISO9660_FS=./CONFIG_ISO9660_FS=y/' $LINUX_DIR/.config

# don't sign modules
sed -i 's/CONFIG_MODULE_SIG=y/CONFIG_MODULE_SIG=n/' $LINUX_DIR/.config

# this modules has unsatisfed dependencies:
sed -i 's/CONFIG_IMG_ASCII_LCD=m/CONFIG_IMG_ASCII_LCD=n/' $LINUX_DIR/.config

# disable RODATA for now 
sed -i 's/CONFIG_DEBUG_RODATA_TEST=y/CONFIG_DEBUG_RODATA_TEST=n/' $LINUX_DIR/.config

# prepare init ram disk
sed -i "s@CONFIG_INITRAMFS_SOURCE=\"\"@CONFIG_INITRAMFS_SOURCE=\"$INITRD_DIR/files\"@" $LINUX_DIR/.config
echo "CONFIG_INITRAMFS_ROOT_UID=-1" >> $LINUX_DIR/.config
echo "CONFIG_INITRAMFS_ROOT_GID=-1" >> $LINUX_DIR/.config

# ?? don't know
echo "CONFIG_BIG_KEYS=y" >> $LINUX_DIR/.config

# create initrd that mount --bind /dev/ubdd over /dev/ubda1
cat > $INITRD_DIR/files << EOF
dir /dev         0755 0 0
nod /dev/console 0600 0 0 c 5 1
nod /dev/ubda1   0600 0 0 b 98 1
nod /dev/ubdd    0600 0 0 b 98 48 
dir /root        0700 0 0
dir /sysroot     0755 0 0
dir /modules     0755 0 0
dir /sbin        0755 0 0
file /sbin/init $INITRD_DIR/init 0755 0 0
EOF
#rm -R $INITRD_DIR
#file /sbin/init $INITRD_DIR/init 0755 0 0

# build kernel
# combined targets "clean all" fail :-(
#make -C $LINUX_DIR -j$(nproc) clean 
make -C $LINUX_DIR -j$(nproc) all

# build and install kselftests
# used by kselftest install
export INSTALL_PATH=`mktemp -d`
make -C $LINUX_DIR/tools/testing/selftests all install
mke2fs -F -d $INSTALL_PATH $KSELFTEST_FILE 512m
rm -R $INSTALL_PATH

# build and install modules 
export INSTALL_MOD_PATH=`mktemp -d`
make -C $LINUX_DIR modules_install 
mke2fs -F -d $INSTALL_MOD_PATH $MODULES_FILE 1g 
rm -R $INSTALL_MOD_PATH

#root=/dev/ubda1 
$LINUX_DIR/linux mem=1280m umid=kselftests ubd0=$RAW_FILE.cow,$RAW_FILE ubd1=$CLOUD_INIT_FILE ubd2=$KSELFTEST_FILE ubd3=$MODULES_FILE ro rhgb quiet LANG=de_DE.UTF-8 plymouth.enable=0 con=pts con0=fd:0,fd:1 loadpin.enabled=0 rootfstype=ramfs

