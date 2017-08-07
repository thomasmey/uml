#!/bin/sh

export ARCH=um
# x86_64 or i386
export SUBARCH=x86_64

LINUX_DIR=~/git/linux

RAW_FILE=Fedora-Cloud-Base-26-1.5.x86_64.raw
CLOUD_INIT_FILE=Fedora-Cloud-Base-Init.iso
KSELFTEST_FILE=Fedora-Cloud-Base-kselftests.img


if [ ! -d "$LINUX_DIR" ]; then
  mkdir -p $LINUX_DIR
  git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git $LINUX_DIR
fi

if [ ! -f "$RAW_FILE" ]; then
  curl -OL "https://download.fedoraproject.org/pub/fedora/linux/releases/26/CloudImages/x86_64/images/$RAW_FILE.xz"
  unxz $RAW_FILE.xz
fi

if [ ! -f "$CLOUD_INIT_FILE" ]; then
  { echo instance-id: iid-local01; echo local-hostname: cloudimg; } > meta-data
  cat > user-data << EOF
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
  genisoimage -output $CLOUD_INIT_FILE -volid cidata -joliet -rock user-data meta-data
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

# build kernel
make -C $LINUX_DIR -j$(nproc) all

# build and install kselftests
# used by kselftest install
export INSTALL_PATH=`mktemp -d`
make -C $LINUX_DIR/tools/testing/selftests all install
mke2fs -F -d $INSTALL_PATH $KSELFTEST_FILE 512m
rm -R $INSTALL_PATH

$LINUX_DIR/linux mem=1280m umid=kselftests ubd0=$RAW_FILE.cow,$RAW_FILE ubd1=$CLOUD_INIT_FILE ubd2=$KSELFTEST_FILE root=/dev/ubda1 ro rhgb quiet LANG=de_DE.UTF-8 plymouth.enable=0 con=pts con0=fd:0,fd:1

