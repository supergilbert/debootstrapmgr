#!/bin/sh -ex

export DEBIAN_FRONTEND="noninteractive"

losetup --raw

apt update

apt -y upgrade

apt -y install apt-utils debhelper devscripts expect qemu-system-x86

cp -R src/debian_tmp ./debian
cp debian/no_qemu_version_control debian/control

debuild -b -us -uc

mkdir -p /tmp/repo/pkg

cp ../debian-generator_$(dpkg-parsechangelog -l debian/changelog -S Version)_$(dpkg --print-architecture).deb /tmp/repo/pkg

cd /tmp/repo
apt-ftparchive packages pkg > pkg/Packages
cd -

echo "Archive: dmgrtmp\nArchitecture: $(dpkg --print-architecture)" > /tmp/repo/Release

echo "deb [trusted=yes] file:///tmp/repo/ pkg/" > /etc/apt/sources.list.d/dmgrtmp.list

apt update

apt -y install debian-generator

TEST_CHROOT_PATH=./test_chroot

if losetup --raw | grep -q ${TEST_CHROOT_PATH}.img; then
    echo "Environment is not clean (loop device bound on destination image)"
    exit 1
fi

debgen pc-debootstrap -d $TEST_CHROOT_PATH

cat <<EOF > ${TEST_CHROOT_PATH}/root/run_test.sh
#!/bin/sh

echo "DEBG OK"
EOF
chmod +x ${TEST_CHROOT_PATH}/root//run_test.sh

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

debgen pc-flash -s $TEST_CHROOT_PATH -d ${TEST_CHROOT_PATH}.img

cat <<EOF > /tmp/dmgr_expect_test
#!/usr/bin/expect -f

set timeout 300

spawn qemu-system-x86_64 -nographic -m 1G $DEBG_KVM_OPTION -drive format=raw,file=${TEST_CHROOT_PATH}.img

expect {
  "DEBG OK" { exit 0 }
  timeout { exit 1 }
}
EOF
chmod +x /tmp/dmgr_expect_test

/tmp/dmgr_expect_test
