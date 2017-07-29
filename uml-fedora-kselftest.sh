#!/bin/sh

# x86_64 or i386
SUBARCH=x86_64

LINUX_DIR=/home/thomas/git/linux

RAW_FILE=Fedora-Cloud-Base-26-1.5.x86_64.raw
CLOUD_INIT_FILE=Fedora-Cloud-Base-Init.iso


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
 - [ "/dev/ubdc", "/opt" ]

EOF

  ## create a disk to attach with some user-data and meta-data
  genisoimage -output $CLOUD_INIT_FILE -volid cidata -joliet -rock user-data meta-data
fi

# build kernel
make ARCH=um -C $LINUX_DIR/ -j$(nproc) defconfig all

# build and install kselftests
# used by kselftest install
export INSTALL_PATH=`mktemp -d`
make -C $LINUX_DIR/tools/testing/selftests all install
mke2fs -F -d /tmp/tmp.sPbFbnhSof/ Fedora-Cloud-Base-kselftests.img 256m
rm -R $INSTALL_PATH

$LINUX_DIR/linux mem=1280m umid=fedora-cloud-base ubd0=$RAW_FILE.cow,$RAW_FILE ubd1=$CLOUD_INIT_FILE ubd2=Fedora-Cloud-Base-kselftests.img root=/dev/ubda1 ro rhgb quiet LANG=de_DE.UTF-8 plymouth.enable=0 con=pts con0=fd:0,fd:1

