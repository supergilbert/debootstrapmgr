#!/bin/sh -ex

if [ "$(id -u)" != 0 ]; then
    echo "Need root privilegies"
    exit 0
fi

SRCDIR=$(realpath $(dirname $0)/..)

cd $SRCDIR
debuild -b -us -uc
cd -

PKGPATH=${SRCDIR}/../debootstrapmgr_$(dpkg-parsechangelog -l ${SRCDIR}/debian/changelog -S Version)_$(dpkg --print-architecture).deb

${SRCDIR}/debootstrapmgr.sh pc-debootstrap -d /tmp/dmgr_test_chroot -r phenom:3142/ftp.free.fr/debian

cp $PKGPATH /tmp/dmgr_test_chroot/tmp
PKGFILE=$(basename $PKGPATH)

cat <<EOF > /tmp/dmgr_test_stage2.sh
#!/bin/sh -x

apt update
dpkg -i /tmp/${PKGFILE}
apt -f -y install
EOF
chmod +x /tmp/dmgr_test_stage2.sh

${SRCDIR}/debootstrapmgr.sh chroot-exec -d /tmp/dmgr_test_chroot -e /tmp/dmgr_test_stage2.sh

rm -f /tmp/dmgr_test_stage2.sh

cat <<EOF > /tmp/dmgr_test_chroot/root/dmgr_test_stage3.sh
#!/bin/sh -ex

dhclient ens3

dpkg --add-architecture armhf

apt update

apt upgrade -y

export DMGR_DEBUG=ON

debootstrapmgr rpi-debootstrap -C phenom:3142 -d /tmp/dmgr_test_chroot
debootstrapmgr rpi-chroot-flash -s /tmp/dmgr_test_chroot -d /tmp/test.img
rm -f /tmp/test.img
debootstrapmgr rpi-chroot-flash -s /tmp/dmgr_test_chroot -d /dev/sdb
rm -rf /tmp/dmgr_test_chroot
debootstrapmgr pc-debootstrap -d /tmp/dmgr_test_chroot -r phenom:3142/ftp.free.fr/debian
debootstrapmgr pc-chroot-flash -s /tmp/dmgr_test_chroot -d /tmp/test.img
rm -f /tmp/test.img
debootstrapmgr pc-chroot-flash -s /tmp/dmgr_test_chroot -d /dev/sdb
sleep 10s
poweroff
EOF
chmod +x /tmp/dmgr_test_chroot/root/dmgr_test_stage3.sh

mkdir -p /tmp/dmgr_test_chroot/etc/systemd/system/getty@ttyS0.service.d
cat <<EOF > /tmp/dmgr_test_chroot/etc/systemd/system/getty@ttyS0.service.d/override.conf
[Unit]
Description=Test debootstrapmgr

[Service]
Restart=no
ExecStart=
ExecStart=-/root/dmgr_test_stage3.sh
Type=oneshot
RemainAfterExit=no
StandardInput=tty
StandardOutput=tty
EOF

${SRCDIR}/debootstrapmgr.sh chroot /tmp/dmgr_test_chroot systemctl enable getty@ttyS0.service

${SRCDIR}/debootstrapmgr.sh pc-chroot-flash -S 10 -s /tmp/dmgr_test_chroot -d /tmp/dmgr_test_chroot.img

rm -rf /tmp/dmgr_test_chroot

truncate -s 5G /tmp/dmgr_test_disk2.img

kvm -m 2G -serial stdio -drive format=raw,file=/tmp/dmgr_test_chroot.img -drive format=raw,file=/tmp/dmgr_test_disk2.img

rm -f /tmp/dmgr_test_chroot.img /tmp/dmgr_test_disk2.img
