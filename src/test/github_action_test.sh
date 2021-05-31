#!/bin/sh -ex

export DEBIAN_FRONTEND="noninteractive"

apt update

apt -y upgrade

apt -y install apt-utils debhelper devscripts expect qemu-system-x86

./make_deb.sh debian-no-qemu-version-dep
./make_deb.sh build

mkdir -p /tmp/repo/pkg

cp ../debgen_$(dpkg-parsechangelog -l debian/changelog -S Version)_amd64.deb /tmp/repo/pkg
cp ../*.deb /tmp/repo/pkg

cd /tmp/repo
apt-ftparchive packages pkg > pkg/Packages
cd -

echo "Archive: debgtmp\nArchitecture: $(dpkg --print-architecture)" > /tmp/repo/Release

echo "deb [trusted=yes] file:///tmp/repo/ pkg/" > /etc/apt/sources.list.d/debgtmp.list

apt update

apt -y install debgen

TEST_CHROOT_PATH=./test_chroot

if losetup --raw | grep -q ${TEST_CHROOT_PATH}.img; then
    echo "Environment is not clean (loop device bound on destination image)"
    exit 1
fi

debgen pc-chroot -d $TEST_CHROOT_PATH

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

if losetup --raw | grep -q ${TEST_CHROOT_PATH}.img; then
    echo "\n\n\nEnvironment is not clean (loop device bound on destination image)\n\n"
else
    echo "Loop device unmapped successfully from destination file"
fi

cat <<EOF > /tmp/debg_expect_test
#!/usr/bin/expect -f

set timeout 300

spawn qemu-system-x86_64 -nographic -m 1G $DEBG_KVM_OPTION -drive format=raw,file=${TEST_CHROOT_PATH}.img

expect {
  "DEBG OK" { send_log "\nSystem boot kvm ok\n\n" ; exit 0 }
  timeout { send_error "\nSystem boot kvm timed out\n\n" ; exit 1 }
}
EOF
chmod +x /tmp/debg_expect_test
/tmp/debg_expect_test
