#!/bin/sh -ex

if [ "$(id -u)" != 0 ]; then
    echo "Need root privilegies"
    exit 0
fi

export DEBG_DEBUG=ON

SRCDIR=$(realpath $(dirname $0)/../..)

cp -R src/debian_tmp ./debian

cd $SRCDIR
debuild -b -us -uc
cd -
PKGPATH=${SRCDIR}/../debian-generator_$(dpkg-parsechangelog -l ${SRCDIR}/debian/changelog -S Version)_all.deb


TEST_CHROOT_PATH="/tmp/debg_test_chroot"
TEST_SCRIPT="/root/debg_test.sh"

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


if [ ! -d ${TEST_CHROOT_PATH} ]; then
    # need qemu-user-static >= 1:5.0.4 to run rpi emulation with "raspi-copy-n-..." package installed (bullseye dist do the hack)
    debgen pc-debootstrap -d $TEST_CHROOT_PATH -r phenom:3142/ftp.free.fr/debian -D bullseye -a expect -a procps -a debianutils -a psmisc -i $PKGPATH
    cp ${SRCDIR}/src/test/scenario_echo_debg_ok.sh ${TEST_CHROOT_PATH}/root
    cp ${SRCDIR}/src/test/scenario_create_systems.sh ${TEST_CHROOT_PATH}/root/run_test.sh

    add_ttyS0_service ${TEST_CHROOT_PATH} /root/run_test.sh
else
    cp ${SRCDIR}/src/test/scenario_create_systems.sh ${TEST_CHROOT_PATH}/root/run_test.sh
    cp ${SRCDIR}/src/test/scenario_echo_debg_ok.sh ${TEST_CHROOT_PATH}/root
fi

cat <<EOF > /tmp/debg_test_grubcfg.sh
#!/bin/sh -x
echo "GRUB_TIMEOUT=0" > /etc/default/grub.d/debgtest.cfg
EOF
chmod +x /tmp/debg_test_grubcfg.sh

debgen pc-flash -S 10 -s $TEST_CHROOT_PATH -d ${TEST_CHROOT_PATH}.img -i $PKGPATH -e /tmp/debg_test_grubcfg.sh

rm /tmp/debg_test_grubcfg.sh

trap "rm -f ${TEST_CHROOT_PATH}.img /tmp/debg_test_disk2.img /tmp/debg_test_disk3.img /tmp/debg_expect_test.sh" INT TERM EXIT

truncate -s 5G /tmp/debg_test_disk2.img
truncate -s 5G /tmp/debg_test_disk3.img

if [ "$1" = "-g" -o "$1" = "--graphic" ]; then
    DEBG_KVM_OPTION="-serial stdio"
else
    DEBG_KVM_OPTION="-nographic"
fi

cat <<EOF > /tmp/debg_expect_test.exp
#!/usr/bin/expect -f

# Generate new images into kvm (with scenario_create_systems.sh)

set timeout 3600

spawn kvm -m 2G $DEBG_KVM_OPTION -drive format=raw,file=${TEST_CHROOT_PATH}.img -drive format=raw,file=/tmp/debg_test_disk2.img -drive format=raw,file=/tmp/debg_test_disk3.img
expect {
 "DEBG_ERROR" { send_error "\nSystems creation kvm failed creation\n\n" ; exit 1 }
 timeout { send_error "\nSystems creation kvm timed out\n\n" ; exit 1 }
 eof { send_log "\nSystems creation ok\n\n" }
}


# Test pc image generated from scenario_create_systems.sh (with scenario_echo_debg_ok.sh)
# (test boot)

set timeout 180

spawn kvm -m 2G $DEBG_KVM_OPTION -drive format=raw,file=/tmp/debg_test_disk2.img
expect {
 "DEBG OK" { send_log "\nSystem boot kvm ok\n\n" ; close }
 timeout { send_error "\nSystem boot kvm timed out\n\n" ; exit 1 }
}

spawn kvm -m 2G $DEBG_KVM_OPTION -drive format=raw,file=/tmp/debg_test_disk3.img
expect {
 "DEBG OK" { send_log "\nSystem boot kvm ok\n\n" ; exit 0 }
 timeout { send_error "\nSystem boot kvm timed out\n\n" ; exit 1 }
}
EOF
chmod +x /tmp/debg_expect_test.exp
/tmp/debg_expect_test.exp


trap - INT TERM EXIT

rm -f ${TEST_CHROOT_PATH}.img /tmp/debg_test_disk2.img /tmp/debg_test_disk3.img /tmp/debg_expect_test.exp
