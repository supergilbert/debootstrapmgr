#!/bin/sh -e

trap "echo '\nDMGR_ERROR\n'" INT TERM EXIT

dhclient ens3

dpkg --add-architecture armhf

apt update

TEST_CHROOT_PATH="/tmp/dmgr_test_chroot"

export DMGR_DEBUG=ON

add_ttyS0_service ()
{
    mkdir -p ${1}/etc/systemd/system/getty@ttyS0.service.d
    cat <<EOF > ${1}/etc/systemd/system/getty@ttyS0.service.d/override.conf
[Unit]
Description=Test debootstrapmgr

[Service]
Restart=no
ExecStart=
ExecStart=-/root/run_test.sh
Type=oneshot
RemainAfterExit=no
StandardInput=tty
StandardOutput=tty
EOF
    debootstrapmgr chroot $1 systemctl enable getty@ttyS0.service
}

debootstrapmgr rpi-debootstrap -C phenom:3142 -d ${TEST_CHROOT_PATH}
cp /root/scenario_echo_dmgr_ok.sh ${TEST_CHROOT_PATH}/root/run_test.sh
add_ttyS0_service $TEST_CHROOT_PATH

debootstrapmgr mklive-squashfs -s ${TEST_CHROOT_PATH} -d /tmp/test.img
rm -f /tmp/test.img

debootstrapmgr rpi-flash -s ${TEST_CHROOT_PATH} -d /tmp/test.img
rm -f /tmp/test.img

debootstrapmgr rpi-flash -s ${TEST_CHROOT_PATH} -d /dev/sdb


rm -rf ${TEST_CHROOT_PATH}


debootstrapmgr pc-debootstrap -d ${TEST_CHROOT_PATH} -r phenom:3142/ftp.free.fr/debian
cp /root/scenario_echo_dmgr_ok.sh ${TEST_CHROOT_PATH}/root/run_test.sh
add_ttyS0_service $TEST_CHROOT_PATH

debootstrapmgr mklive-squashfs -s ${TEST_CHROOT_PATH} -d /tmp/test.img
rm -f /tmp/test.img

debootstrapmgr pc-flash -s ${TEST_CHROOT_PATH} -d /tmp/test.img
rm -f /tmp/test.img

debootstrapmgr pc-flash-live -s ${TEST_CHROOT_PATH} -d /dev/sdc

trap - INT TERM EXIT

poweroff
