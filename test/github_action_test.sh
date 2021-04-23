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

debootstrapmgr pc-debootstrap -d ./test_chroot

debootstrapmgr pc-flash -s ./test_chroot -d ./test_chroot.img

#kvm -m 1G -nographic -drive format=raw,file=./test_chroot.img
