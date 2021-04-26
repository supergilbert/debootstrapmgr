#!/bin/sh -ex

export DEBIAN_FRONTEND="noninteractive"

apt update

apt -y upgrade

apt -y install apt-utils debhelper devscripts expect qemu-system-x86

rm -rf debian
cp -R ubuntu_20.04 debian

debuild -b -us -uc

mkdir -p /tmp/repo/pkg

cp ../debootstrapmgr_$(dpkg-parsechangelog -l debian/changelog -S Version)_$(dpkg --print-architecture).deb /tmp/repo/pkg

cd /tmp/repo
apt-ftparchive packages pkg > pkg/Packages
cd -

echo "Archive: dmgrtmp\nArchitecture: $(dpkg --print-architecture)" > /tmp/repo/Release

echo "deb [trusted=yes] file:///tmp/repo/ pkg/" > /etc/apt/sources.list.d/dmgrtmp.list

apt update

apt -y install debootstrapmgr

TEST_CHROOT_PATH=./test_chroot

debootstrapmgr pc-debootstrap -d $TEST_CHROOT_PATH

cat <<EOF > ${TEST_CHROOT_PATH}/root//run_test.sh
#!/bin/sh

echo "DMGR OK"
EOF
chmod +x ${TEST_CHROOT_PATH}/root//run_test.sh

mkdir -p ${TEST_CHROOT_PATH}/etc/systemd/system/getty@ttyS0.service.d
cat <<EOF > ${TEST_CHROOT_PATH}/etc/systemd/system/getty@ttyS0.service.d/override.conf
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
debootstrapmgr chroot $TEST_CHROOT_PATH systemctl enable getty@ttyS0.service


debootstrapmgr pc-flash -s $TEST_CHROOT_PATH -d ${TEST_CHROOT_PATH}.img

cat <<EOF > /tmp/dmgr_expect_test
#!/usr/bin/expect -f

set timeout 180

spawn qemu-system-x86_64 -nographic -m 1G $DMGR_KVM_OPTION -drive format=raw,file=${TEST_CHROOT_PATH}.img

expect {
  "DMGR OK" { exit 0 }
  timeout { exit 1 }
}
EOF
chmod +x /tmp/dmgr_expect_test

/tmp/dmgr_expect_test
