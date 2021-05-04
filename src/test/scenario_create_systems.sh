#!/bin/sh -e

trap "echo '\nDEBG_ERROR\n'" INT TERM EXIT

dhclient ens3

dpkg --add-architecture armhf

apt update

TEST_CHROOT_PATH="/tmp/debg_test_chroot"

export DEBG_DEBUG=ON

add_ttyS0_service ()
{
    mkdir -p ${1}/etc/systemd/system/getty@ttyS0.service.d
    cat <<EOF > ${1}/etc/systemd/system/getty@ttyS0.service.d/override.conf
[Unit]
Description=Test debian-generator

[Service]
Restart=no
ExecStart=
ExecStart=-${2}
Type=oneshot
RemainAfterExit=no
StandardInput=tty
StandardOutput=tty
EOF
    debgen chroot $1 systemctl enable getty@ttyS0.service
}

# Test rpi generation

debgen rpi-debootstrap -C phenom:3142 -d ${TEST_CHROOT_PATH}
cp /root/scenario_echo_debg_ok.sh ${TEST_CHROOT_PATH}/root/run_test.sh
add_ttyS0_service $TEST_CHROOT_PATH /root/run_test.sh

debgen mklive-squashfs -s ${TEST_CHROOT_PATH} -d /tmp/test.squashfs
rm -f /tmp/test.squashfs

debgen rpi-flash -s ${TEST_CHROOT_PATH} -d /tmp/test.img
if losetup --raw | grep -q ${TEST_CHROOT_PATH}.img; then
    echo "ERROR: Loop device still bind ${TEST_CHROOT_PATH}.img"
    exit 1
fi
rm -f /tmp/test.img

debgen rpi-flash-live -s ${TEST_CHROOT_PATH} -d /dev/sdb

debgen rpi-flash -s ${TEST_CHROOT_PATH} -d /dev/sdc


rm -rf ${TEST_CHROOT_PATH}

# Test pc generation

debgen pc-debootstrap -d ${TEST_CHROOT_PATH} -r phenom:3142/ftp.free.fr/debian
cp /root/scenario_echo_debg_ok.sh ${TEST_CHROOT_PATH}/root/run_test.sh
add_ttyS0_service $TEST_CHROOT_PATH /root/run_test.sh

debgen mklive-squashfs -s ${TEST_CHROOT_PATH} -d /tmp/test.squashfs
rm -f /tmp/test.squashfs

debgen pc-flash -s ${TEST_CHROOT_PATH} -d /tmp/test.img
if losetup --raw | grep -q ${TEST_CHROOT_PATH}.img; then
    echo "ERROR: Loop device still bind ${TEST_CHROOT_PATH}.img"
    exit 1
fi
rm -f /tmp/test.img

debgen pc-flash-live -s ${TEST_CHROOT_PATH} -d /dev/sdb

debgen pc-flash -s ${TEST_CHROOT_PATH} -d /dev/sdc

trap - INT TERM EXIT

poweroff
