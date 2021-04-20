#!/bin/sh -ex

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

apt install debootstrapmgr

debootstrapmgr pc-debootstrap -d ./test_chroot

debootstrapmgr pc-flash -s ./test_chroot -d ./test_chroot.img

# TODO small test with kvm
