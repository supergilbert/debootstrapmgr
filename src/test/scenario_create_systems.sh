#!/bin/sh -e

trap "echo '\nDEBG_ERROR\n'" INT TERM EXIT

set -x

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

log_stape ()
{
    echo "\n\033[93;4m$*\033[0m\n"
}



# Test rpi generation
log_stape "\n\n*** Test rpi generation ***"

log_stape "Generating rpi chroot"
debgen rpi-debootstrap -C XXXAPTCACHERXXX -d ${TEST_CHROOT_PATH}
cp /root/scenario_echo_debg_ok.sh ${TEST_CHROOT_PATH}/root/run_test.sh
add_ttyS0_service $TEST_CHROOT_PATH /root/run_test.sh

log_stape "Generating rpi squashfs file"
debgen mklive-squashfs -s ${TEST_CHROOT_PATH} -d /tmp/test.squashfs
rm -f /tmp/test.squashfs

log_stape "Generating rpi image file"
debgen rpi-flash -s ${TEST_CHROOT_PATH} -d /tmp/test.img
if losetup --raw | grep -q ${TEST_CHROOT_PATH}.img; then
    echo "ERROR: Loop device still bind ${TEST_CHROOT_PATH}.img"
    exit 1
fi
rm -f /tmp/test.img

log_stape "Generating rpi live system in block device sdb"
debgen rpi-flash-live -s ${TEST_CHROOT_PATH} -d /dev/sdb

log_stape "Generating rpi system in block device sdc"
debgen rpi-flash -s ${TEST_CHROOT_PATH} -d /dev/sdc

rm -rf ${TEST_CHROOT_PATH}



# Test pc generation
log_stape "\n\n*** Test pc generation ***"

log_stape "Generating pc chroot"
debgen pc-debootstrap -d ${TEST_CHROOT_PATH} -r XXXAPTCACHERXXX/ftp.free.fr/debian
mkdir -p ${TEST_CHROOT_PATH}/usr/local/share/debgen_test
cp /root/scenario_echo_debg_ok.sh ${TEST_CHROOT_PATH}/usr/local/share/debgen_test/run_test.sh
add_ttyS0_service $TEST_CHROOT_PATH /usr/local/share/debgen_test/run_test.sh

log_stape "Generating pc image file"
debgen pc-flash -s ${TEST_CHROOT_PATH} -d /tmp/test.img
if losetup --raw | grep -q ${TEST_CHROOT_PATH}.img; then
    echo "ERROR: Loop device still bind ${TEST_CHROOT_PATH}.img"
    exit 1
fi
rm -f /tmp/test.img

log_stape "Generating pc iso file"
debgen pc-flash-iso -s ${TEST_CHROOT_PATH} -d /tmp/test.iso
rm -f /tmp/test.iso

log_stape "Generating pc live system in block device sdb"
debgen pc-flash-live -s ${TEST_CHROOT_PATH} -d /dev/sdb -p /usr/local/share/debgen_test

log_stape "Generating newpc squashfs in previous live system (block device sdb)"
debgen dump-default-live-json > /tmp/dmgr_live.json
diskhdr /tmp/dmgr_live.json mount 0 /dev/sdb /mnt
rm -f /mnt/live/filesystem.squashfs
debgen mklive-squashfs -s ${TEST_CHROOT_PATH} -d /mnt/live/filesystem.squashfs -p /usr/local/share/debgen_test
diskhdr /tmp/dmgr_live.json umount 0 /dev/sdb /mnt

log_stape "Generating pc system in block device sdc"
debgen pc-flash -s ${TEST_CHROOT_PATH} -d /dev/sdc


#END
trap - INT TERM EXIT
poweroff
