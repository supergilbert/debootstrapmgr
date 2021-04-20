#!/bin/sh -ex

if [ "$(id -u)" != 0 ]; then
    echo "Need root privilegies"
    exit 0
fi

export DMGR_DEBUG=ON

SRCDIR=$(realpath $(dirname $0)/..)

cp -r ${SRCDIR}/debian_bullseye ${SRCDIR}/debian

cd $SRCDIR
debuild -b -us -uc
cd -
PKGPATH=${SRCDIR}/../debootstrapmgr_$(dpkg-parsechangelog -l ${SRCDIR}/debian/changelog -S Version)_$(dpkg --print-architecture).deb


TEST_CHROOT_PATH="/tmp/dmgr_test_chroot"
TEST_SCRIPT="/root/dmgr_test.sh"
EXPECT_SCRIPT="/tmp/dmgr_expect.sh"


if [ ! -d ${TEST_CHROOT_PATH} ]; then

    # need qemu-user-static >= 1:5.0.4 to run rpi emulation with "raspi-copy-n-..." package installed (bullseye dist do the hack)
    debootstrapmgr pc-debootstrap -d $TEST_CHROOT_PATH -r phenom:3142/ftp.free.fr/debian -D bullseye -a expect -a procps

    cat <<EOF > ${TEST_CHROOT_PATH}${TEST_SCRIPT}
#!/bin/sh -e


trap "echo '\nDMGR_ERROR\n'" INT TERM EXIT

dhclient ens3

dpkg --add-architecture armhf

apt update

export DMGR_DEBUG=ON

debootstrapmgr rpi-debootstrap -C phenom:3142 -d ${TEST_CHROOT_PATH}

debootstrapmgr mklive-squashfs -s ${TEST_CHROOT_PATH} -d /tmp/test.img
rm -f /tmp/test.img

debootstrapmgr rpi-chroot-flash -s ${TEST_CHROOT_PATH} -d /tmp/test.img
rm -f /tmp/test.img

debootstrapmgr rpi-chroot-flash -s ${TEST_CHROOT_PATH} -d /dev/sdb


rm -rf ${TEST_CHROOT_PATH}


debootstrapmgr pc-debootstrap -d ${TEST_CHROOT_PATH} -r phenom:3142/ftp.free.fr/debian

debootstrapmgr mklive-squashfs -s ${TEST_CHROOT_PATH} -d /tmp/test.img
rm -f /tmp/test.img

debootstrapmgr pc-chroot-flash -s ${TEST_CHROOT_PATH} -d /tmp/test.img
rm -f /tmp/test.img

debootstrapmgr pc-chroot-flash -s ${TEST_CHROOT_PATH} -d /dev/sdb

trap - INT TERM EXIT

poweroff
EOF
    chmod +x ${TEST_CHROOT_PATH}${TEST_SCRIPT}

    mkdir -p ${TEST_CHROOT_PATH}/etc/systemd/system/getty@ttyS0.service.d
    cat <<EOF > ${TEST_CHROOT_PATH}/etc/systemd/system/getty@ttyS0.service.d/override.conf
[Unit]
Description=Test debootstrapmgr

[Service]
Restart=no
ExecStart=
ExecStart=-${TEST_SCRIPT}
Type=oneshot
RemainAfterExit=no
StandardInput=tty
StandardOutput=tty
EOF

    debootstrapmgr chroot $TEST_CHROOT_PATH systemctl enable getty@ttyS0.service

fi

cat <<EOF > /tmp/dmgr_test_grubcfg.sh
#!/bin/sh -x
echo "GRUB_TIMEOUT=0" > /etc/default/grub.d/dmgrtest.cfg
EOF
chmod +x /tmp/dmgr_test_grubcfg.sh

debootstrapmgr pc-chroot-flash -S 10 -s $TEST_CHROOT_PATH -d ${TEST_CHROOT_PATH}.img -i $PKGPATH -e /tmp/dmgr_test_grubcfg.sh

rm /tmp/dmgr_test_grubcfg.sh

# rm -rf ${TEST_CHROOT_PATH}

truncate -s 5G /tmp/dmgr_test_disk2.img

cat <<EOF > $EXPECT_SCRIPT
#!/usr/bin/expect -f

set timeout 1800

#spawn kvm -m 2G -serial stdio -drive format=raw,file=${TEST_CHROOT_PATH}.img -drive format=raw,file=/tmp/dmgr_test_disk2.img
spawn kvm -m 2G -nographic -drive format=raw,file=${TEST_CHROOT_PATH}.img -drive format=raw,file=/tmp/dmgr_test_disk2.img

expect "DMGR_ERROR" { exit 1 }
EOF
chmod +x $EXPECT_SCRIPT

trap "rm -f ${TEST_CHROOT_PATH}.img /tmp/dmgr_test_disk2.img" INT TERM EXIT

$EXPECT_SCRIPT

trap - INT TERM EXIT

rm -f ${TEST_CHROOT_PATH}.img /tmp/dmgr_test_disk2.img
