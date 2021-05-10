#!/bin/sh -e

if [ "$(id -u)" != 0 ]; then
    echo "Need root privilegies"
    exit 1
fi

if [ -z "$DEBGEN_APT_CACHER" ]; then
    echo "\
Need DEBGEN_APT_CACHER environent variable (ADDR:PORT).
(... and an apt-cacher service)"
    exit 1
fi

set -x

export DEBGEN_DEBUG=ON

SRCDIR=$(realpath $(dirname $0)/../..)

${SRCDIR}/make_deb.sh build
PKGPATH=${SRCDIR}/../debgen_$(dpkg-parsechangelog -l ${SRCDIR}/debian/changelog -S Version)_all.deb

TEST_CHROOT_PATH="/tmp/debgen_test_chroot_base"
TEST_TMP_DIR="$(mktemp -d --suffix _debgen_test)"
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
    # need qemu-user-static >= 1:5.0.4 to run rpi emulation with "raspi-copy-n-..." package installed (bullseye dist (currently unstable version) do the hack)
    debgen pc-chroot -d $TEST_CHROOT_PATH -r ${DEBGEN_APT_CACHER}/ftp.free.fr/debian -D bullseye -a expect -a procps -a debianutils -a psmisc -i $PKGPATH
    cp ${SRCDIR}/src/test/scenario_echo_debg_ok.sh ${TEST_CHROOT_PATH}/root
    sed "s/XXXAPTCACHERXXX/${DEBGEN_APT_CACHER}/" ${SRCDIR}/src/test/scenario_create_systems.sh > ${TEST_CHROOT_PATH}/root/run_test.sh
    chmod +x ${TEST_CHROOT_PATH}/root/run_test.sh
    add_ttyS0_service ${TEST_CHROOT_PATH} /root/run_test.sh
else
    cp -f ${SRCDIR}/src/test/scenario_echo_debg_ok.sh ${TEST_CHROOT_PATH}/root
    sed "s/XXXAPTCACHERXXX/${DEBGEN_APT_CACHER}/" ${SRCDIR}/src/test/scenario_create_systems.sh > ${TEST_CHROOT_PATH}/root/run_test.sh
    chmod +x ${TEST_CHROOT_PATH}/root/run_test.sh
fi

TMP_GRUB_CFG="${TEST_TMP_DIR}/test_gen_grubcfg.sh"

cat <<EOF > $TMP_GRUB_CFG
#!/bin/sh -x
echo "GRUB_TIMEOUT=0" > /etc/default/grub.d/debgtest.cfg
EOF
chmod +x $TMP_GRUB_CFG

TEST_QEMU_SDA="${TEST_TMP_DIR}/sda.img"
TEST_QEMU_SDB="${TEST_TMP_DIR}/sdb.img"
TEST_QEMU_SDC="${TEST_TMP_DIR}/sdc.img"

debgen pc-flash -S 10 -s $TEST_CHROOT_PATH -d $TEST_QEMU_SDA -i $PKGPATH -e $TMP_GRUB_CFG

rm $TMP_GRUB_CFG

trap "rm -f ${TEST_TMP_DIR}" INT TERM EXIT

truncate -s 5G $TEST_QEMU_SDB
truncate -s 5G $TEST_QEMU_SDC

if [ "$1" = "-g" -o "$1" = "--graphic" ]; then
    DEBG_KVM_OPTION="-serial stdio"
else
    DEBG_KVM_OPTION="-nographic"
fi

TEST_EXPECT_SCRIPT=${TEST_TMP_DIR}/expect_script.exp

cat <<EOF > $TEST_EXPECT_SCRIPT
#!/usr/bin/expect -f

# Generate new images into kvm (with scenario_create_systems.sh)

set timeout 3600

spawn kvm -m 2G $DEBG_KVM_OPTION -drive format=raw,file=${TEST_QEMU_SDA} -drive format=raw,file=${TEST_QEMU_SDB} -drive format=raw,file=${TEST_QEMU_SDC}
expect {
 "DEBG_ERROR" { send_error "\nSystems creation kvm failed creation\n\n" ; exit 1 }
 timeout { send_error "\nSystems creation kvm timed out\n\n" ; exit 1 }
 eof { send_log "\nSystems creation ok\n\n" }
}


# Test pc image generated from scenario_create_systems.sh (with scenario_echo_debg_ok.sh)
# (test boot)

set timeout 180

spawn kvm -m 2G $DEBG_KVM_OPTION -drive format=raw,file=${TEST_QEMU_SDB}
expect {
 "DEBG OK" { send_log "\nSystem boot kvm ok\n\n" ; close }
 timeout { send_error "\nSystem boot kvm timed out\n\n" ; exit 1 }
}

spawn kvm -m 2G $DEBG_KVM_OPTION -drive format=raw,file=${TEST_QEMU_SDC}
expect {
 "DEBG OK" { send_log "\nSystem boot kvm ok\n\n" ; exit 0 }
 timeout { send_error "\nSystem boot kvm timed out\n\n" ; exit 1 }
}
EOF
chmod +x $TEST_EXPECT_SCRIPT
$TEST_EXPECT_SCRIPT


trap - INT TERM EXIT

rm -rf ${TEST_TMP_DIR}
