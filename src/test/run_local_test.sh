#!/bin/sh -ex

if [ "$(id -u)" != 0 ]; then
    echo "Need root privilegies"
    exit 0
fi

export DEBG_DEBUG=ON

SRCDIR=$(realpath $(dirname $0)/../..)

cp -R src/debian_tmp ./debian
cp debian/no_qemu_version_control debian/control

cd $SRCDIR
debuild -b -us -uc
cd -
PKGPATH=${SRCDIR}/../debian-generator_$(dpkg-parsechangelog -l ${SRCDIR}/debian/changelog -S Version)_$(dpkg --print-architecture).deb


TEST_CHROOT_PATH="/tmp/dmgr_test_chroot"
TEST_SCRIPT="/root/dmgr_test.sh"


if [ ! -d ${TEST_CHROOT_PATH} ]; then

    # need qemu-user-static >= 1:5.0.4 to run rpi emulation with "raspi-copy-n-..." package installed (bullseye dist do the hack)
    debgen pc-debootstrap -d $TEST_CHROOT_PATH -r phenom:3142/ftp.free.fr/debian -D bullseye -a expect -a procps -a debianutils -a psmisc
    cp ${SRCDIR}/src/test/scenario_create_systems.sh ${TEST_CHROOT_PATH}/root/run_test.sh
    cp ${SRCDIR}/src/test/scenario_echo_dmgr_ok.sh ${TEST_CHROOT_PATH}/root

    mkdir -p ${TEST_CHROOT_PATH}/etc/systemd/system/getty@ttyS0.service.d
    cat <<EOF > ${TEST_CHROOT_PATH}/etc/systemd/system/getty@ttyS0.service.d/override.conf
[Unit]
Description=Test debian-generator

[Service]
Restart=no
ExecStart=
ExecStart=-/root/run_test.sh
Type=oneshot
RemainAfterExit=no
StandardInput=tty
StandardOutput=tty
EOF
    debgen chroot $TEST_CHROOT_PATH systemctl enable getty@ttyS0.service

else
    cp ${SRCDIR}/src/test/scenario_create_systems.sh ${TEST_CHROOT_PATH}/root/run_test.sh
    cp ${SRCDIR}/src/test/scenario_echo_dmgr_ok.sh ${TEST_CHROOT_PATH}/root

fi

cat <<EOF > /tmp/dmgr_test_grubcfg.sh
#!/bin/sh -x
echo "GRUB_TIMEOUT=0" > /etc/default/grub.d/dmgrtest.cfg
EOF
chmod +x /tmp/dmgr_test_grubcfg.sh

debgen pc-flash -S 10 -s $TEST_CHROOT_PATH -d ${TEST_CHROOT_PATH}.img -i $PKGPATH -e /tmp/dmgr_test_grubcfg.sh

rm /tmp/dmgr_test_grubcfg.sh

trap "rm -f ${TEST_CHROOT_PATH}.img /tmp/dmgr_test_disk2.img /tmp/dmgr_test_disk3.img /tmp/dmgr_expect_test.sh" INT TERM EXIT

truncate -s 5G /tmp/dmgr_test_disk2.img
truncate -s 5G /tmp/dmgr_test_disk3.img

if [ "$1" = "-g" -o "$1" = "--graphic" ]; then
    DEBG_KVM_OPTION="-serial stdio"
else
    DEBG_KVM_OPTION="-nographic"
fi

# Generate new images into kvm (with scenario_create_systems.sh)
cat <<EOF > /tmp/dmgr_expect_test.sh
#!/usr/bin/expect -f

set timeout 1800

spawn kvm -m 2G $DEBG_KVM_OPTION -drive format=raw,file=${TEST_CHROOT_PATH}.img -drive format=raw,file=/tmp/dmgr_test_disk2.img -drive format=raw,file=/tmp/dmgr_test_disk3.img

expect {
 "DEBG_ERROR" { exit 1 }
 timeout { exit 1 }
}
EOF
chmod +x /tmp/dmgr_expect_test.sh

/tmp/dmgr_expect_test.sh




# Test pc image generated (with scenario_echo_dmgr_ok.sh)
cat <<EOF > /tmp/dmgr_expect_test.sh
#!/usr/bin/expect -f

set timeout 300

spawn kvm -m 2G $DEBG_KVM_OPTION -drive format=raw,file=/tmp/dmgr_test_disk3.img

expect {
 "DEBG OK" { exit 0 }
 timeout { exit 1 }
}
EOF
chmod +x /tmp/dmgr_expect_test.sh

/tmp/dmgr_expect_test.sh





trap - INT TERM EXIT

rm -f ${TEST_CHROOT_PATH}.img /tmp/dmgr_test_disk2.img /tmp/dmgr_test_disk3.img
