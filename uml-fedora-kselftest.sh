#!/bin/bash -e

# This scripts needs those packages:
# - curl
# - genisoimage
# - glibc-static
# - gcc/g++
# - gcc-plugin-dev
# - clang
# - libssl-dev
# - e2fsprogs
# - libelf-dev
# - libcap-dev
# - libcap-ng-dev
# - libfuse-dev
# - libc6-dev
# - libnuma-dev
# - libpopt-dev
# - pkg-config
# - slirp
# - (jq)
# - (uml-utilities)

export ARCH=um
# x86_64 or i386
export SUBARCH=x86_64

LINUX_DIR=~/git/linux

RAW_FILE=Fedora-Cloud-Base-26-1.5.$SUBARCH.raw
CLOUD_INIT_FILE=Fedora-Cloud-Base-Init.iso
KSELFTEST_FILE=Fedora-Cloud-Base-kselftests.img
MODULES_FILE=Fedora-Cloud-Base-modules.img
INITRD_DIR=`mktemp -d`
RESULT_FILE=Fedora-Cloud-Base-Result.img

#export KBUILD_OUTPUT=/home/thomas/git/linux-um/
export KBUILD_OUTPUT=`mktemp -d`

COV_HTML_OUT=coverage

# clone source repo
if [ ! -d "$LINUX_DIR" ]; then
  mkdir -p $LINUX_DIR
  git clone https://github.com/thomasmey/linux.git $LINUX_DIR
fi

# download iso image
if [ ! -f "$RAW_FILE" ]; then
  curl -OL "https://download.fedoraproject.org/pub/fedora/linux/releases/26/CloudImages/$SUBARCH/images/$RAW_FILE.xz"
  unxz $RAW_FILE.xz
fi

# create cloud-init image
TEMP_DIR=`mktemp -d`
cat > $TEMP_DIR/meta-data << EOF
instance-id: iid-local01
local-hostname: cloudimg
network-interfaces: |
  iface eth0 inet static
  address 10.0.2.15
  network 10.0.2.0
  netmask 255.255.255.0
  broadcast 10.0.2.255
  gateway 10.0.2.2 
hostname: cloudimg 
EOF

cat > $TEMP_DIR/user-data << EOF
#cloud-config
password: passw0rd
chpasswd: { expire: False }
ssh_pwauth: True

mounts:
 - [ /dev/ubdc, /opt, ext4 ]

write_files:
 - content: |
     [Unit]
     Description=kselftests
     [Install]
     WantedBy=multi-user.target
     [Service]
     Type=simple
     ExecStart=/bin/sh /opt/run_kselftest.sh
     ExecStopPost=/bin/sh -c "/bin/journalctl -b -o json --no-pager > /dev/ubde"
     ExecStopPost=/usr/bin/systemctl --no-block poweroff
     RuntimeMaxSec=3h
     WorkingDirectory=/opt/
     StandardOutput=journal+console
   path: /etc/systemd/system/kselftests.service
   permissions: '0644'
 - content: |
     isofs
     fuse
   path: /etc/modules-load.d/kselftest-modules.conf
   permissions: '0644'

ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAGEA3FSyQwBI6Z+nCSjUUk8EEAnnkhXlukKoUPND/RRClWz2s5TCzIkd3Ou5+Cyz71X0XmazM3l5WgeErvtIwQMyT1KjNoMhoJMrJnWqQPOt5Q8zWd9qG7PBl9+eiH5qV7NZ mykey@host

runcmd:
  - [ systemctl, daemon-reload ]
  - [ systemctl, enable, kselftests.service ]
  - [ systemctl, start, --no-block, kselftests.service ]

packages:
 - bc
 - perl

manage_resolv_conf: true

resolv_conf:
  nameservers: ['10.0.2.3']

EOF
genisoimage -output $CLOUD_INIT_FILE -volid cidata -joliet -rock $TEMP_DIR
rm -R $TEMP_DIR

# create config
make -C $LINUX_DIR allmodconfig

# Fedora doesn't have this package available
sed -i 's/CONFIG_UML_NET_VDE=y/CONFIG_UML_NET_VDE=n/' $KBUILD_OUTPUT/.config
# pcap is broken
sed -i 's/CONFIG_UML_NET_PCAP=y/CONFIG_UML_NET_PCAP=n/' $KBUILD_OUTPUT/.config

# link dynamic
sed -i 's/CONFIG_STATIC_LINK=y/CONFIG_STATIC_LINK=n/' $KBUILD_OUTPUT/.config

# FIXME: it's either GCOV or GCOV_KERNEL
sed -i 's/CONFIG_GCOV_KERNEL=y/CONFIG_GCOV_KERNEL=n/' $KBUILD_OUTPUT/.config

# this fails
sed -i 's/CONFIG_OF_UNITTEST=y/CONFIG_OF_UNITTEST=n/' $KBUILD_OUTPUT/.config

# increase stack size
sed -i 's/CONFIG_KERNEL_STACK_ORDER=./CONFIG_KERNEL_STACK_ORDER=3/' $KBUILD_OUTPUT/.config

# we need ext4
sed -i 's/CONFIG_EXT4_FS=./CONFIG_EXT4_FS=y/' $KBUILD_OUTPUT/.config

# don't sign modules
sed -i 's/CONFIG_MODULE_SIG=y/CONFIG_MODULE_SIG=n/' $KBUILD_OUTPUT/.config

# disable RODATA for now 
sed -i 's/CONFIG_DEBUG_RODATA_TEST=y/CONFIG_DEBUG_RODATA_TEST=n/' $KBUILD_OUTPUT/.config

# udev fails with this
sed -i 's/CONFIG_SYSFS_DEPRECATED=y/CONFIG_SYSFS_DEPRECATED=n/' $KBUILD_OUTPUT/.config

# prepare init ram disk
sed -i "s@CONFIG_INITRAMFS_SOURCE=\"\"@CONFIG_INITRAMFS_SOURCE=\"$INITRD_DIR/files\"@" $KBUILD_OUTPUT/.config
echo "CONFIG_INITRAMFS_ROOT_UID=-1" >> $KBUILD_OUTPUT/.config
echo "CONFIG_INITRAMFS_ROOT_GID=-1" >> $KBUILD_OUTPUT/.config

# increase kernel message log buffer size
sed -i "s/CONFIG_LOG_BUF_SHIFT=\d+/CONFIG_LOG_BUF_SHIFT=19/" $KBUILD_OUTPUT/.config

# ?? don't know
echo "CONFIG_BIG_KEYS=y" >> $KBUILD_OUTPUT/.config

# disable KCOV
sed -i 's/CONFIG_KCOV=y/CONFIG_KCOV=n/' $KBUILD_OUTPUT/.config

# host systems kmod may lack gzip support, so don't compress modules
sed -i 's/CONFIG_MODULE_COMPRESS=y/CONFIG_MODULE_COMPRESS=n/' $KBUILD_OUTPUT/.config

# disable CONFIG_MODVERSIONS, because it generates temporary object files (see scripts/Makefile.build, cmd_modversions_c)
# which results in .tmp*.gcno/gcda files for GCOV :-(
#sed -i 's/CONFIG_MODVERSIONS=y/CONFIG_MODVERSIONS=n/' $KBUILD_OUTPUT/.config

RESULT_DIR=`make -s -C $LINUX_DIR kernelrelease`
if [ ! -d "$RESULT_DIR" ]; then
  mkdir $RESULT_DIR
fi

# create init helper (mount --bind modules over root)
cc -o $INITRD_DIR/init -static -xc - << EOF
#define _GNU_SOURCE         /* See feature_test_macros(7) */
#include <unistd.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>   /* For SYS_xxx definitions */
#include <sys/mount.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>

static void setup_stdio(void) {
  int confd = open("/dev/console", O_RDWR); 
  dup2(confd, 0);
  dup2(confd, 1);
  dup2(confd, 2);
  close(confd);
}

int main(void) {

  char* newroot = "/sysroot";
  char* modules = "/modules";

  // establish stdin,stdout,stderr
  setup_stdio();

  // mount root
  int rc = mount("/dev/ubda1", newroot, "ext4", 0, "");
  printf("Mounted sysroot with %i\n", rc);
  chdir(newroot);

  // mount bind modules
  rc = mount("/dev/ubdd", modules, "ext4", 0, "");
  printf("Mounted modules with %i\n", rc);
  rc = mount("/modules/lib/modules/", "/sysroot/lib/modules", NULL, MS_BIND, NULL);
  printf("Bound modules with %i\n", rc);

  // move to new root fs
  rc = mount(newroot, "/", NULL, MS_MOVE, NULL);
  printf("Moved sysroot with %i\n", rc);

  chroot(".");
  // establish stdin,stdout,stderr
  setup_stdio();

  // load extra modules for allmodconfig 
  system("/sbin/modprobe binfmt_script");
  system("/sbin/modprobe isofs"); // sadly cloud-init runs too early to use modules-load.d service :-(

  // call original init
  execl("/sbin/init", "/sbin/init", (char*) NULL);
  //return 0;
}
EOF

# create initrd 
cat > $INITRD_DIR/files << EOF
dir /dev         0755 0 0
nod /dev/console 0600 0 0 c 5 1
nod /dev/ubda1   0600 0 0 b 98 1
nod /dev/ubdd    0600 0 0 b 98 48 
dir /sysroot     0755 0 0
dir /modules     0755 0 0
file /init $INITRD_DIR/init 0755 0 0
EOF

# build kernel
make -C $LINUX_DIR -j$(nproc) all 2> $RESULT_DIR/result-kernel-build-stderr.txt

# clean up INITRD_DIR after build
rm -R $INITRD_DIR

# extract "cyclomatic complexity"
grep "Cyclomatic Compl" $RESULT_DIR/result-kernel-build-stderr.txt  | sort -k 3nr > $RESULT_DIR/result-cyc-comp.txt 

# build and install modules 
export INSTALL_MOD_PATH=`mktemp -d`
make -C $LINUX_DIR modules_install 
/sbin/mke2fs -F -d $INSTALL_MOD_PATH $MODULES_FILE 1g 
rm -R $INSTALL_MOD_PATH

# build and install kselftests
# un-export KBUILD_OUTPUT, we don't want to mingle the kernel's code coverage with the kselftests programs,
# which also seems to be build with lgcov?!
declare +x KBUILD_OUTPUT
# used by kselftest install
export INSTALL_PATH=`mktemp -d`
make -C $LINUX_DIR/tools/testing/selftests all install

# this testprogram hangs, for whatever reasons, remove it for now:
#rm $INSTALL_PATH/timers/set-timer-lat
/sbin/mke2fs -F -d $INSTALL_PATH $KSELFTEST_FILE 512m
rm -R $INSTALL_PATH

#prepare output file
truncate -s 512m $RESULT_FILE

#root=/dev/ubda1 
$KBUILD_OUTPUT/linux mem=1280m umid=kselftests-$RANDOM ubd0=$RAW_FILE.cow,$RAW_FILE ubd1=$CLOUD_INIT_FILE ubd2=$KSELFTEST_FILE ubd3=$MODULES_FILE ubd4=$RESULT_FILE ro rhgb quiet LANG=de_DE.UTF-8 plymouth.enable=0 con=pts con0=fd:0,fd:1 eth0=slirp, loadpin.enabled=0 selinux=0

# Extract code coverage
lcov --capture --directory $KBUILD_OUTPUT --output-file coverage.info
genhtml coverage.info --output-directory $RESULT_DIR/$COV_HTML_OUT

# Extract output from this run
jq -r 'select(._SYSTEMD_UNIT == "kselftests.service") | .MESSAGE' $RESULT_FILE > $RESULT_DIR/result-kselftests.txt
jq -r 'select(.SYSLOG_FACILITY == "0") | .MESSAGE' $RESULT_FILE > $RESULT_DIR/result-kernel-log.txt

#rm $KBUILD_OUTPUT

