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

# cat <<EOF > /tmp/dmgr_test_stage3.sh
# #!/bin/sh -x

# debootstrapmgr help
# EOF

# mkdir -p /tmp/dmgr_test_chroot/etc/systemd/system/getty@tty1.service.d
# cat <<EOF > /tmp/dmgr_test_chroot/etc/systemd/system/getty@tty1.service.d/override.conf
# [Unit]
# Description=Test debootstrapmgr

# [Service]
# ExecxStart=
# ExecxStart=-/root/dmgr_test_stage3.sh
# Type=oneshot
# RemainAfterExit=no
# StandardInput=tty
# StandardOutput=tty
# EOF

${SRCDIR}/debootstrapmgr.sh pc-chroot-flash -s /tmp/dmgr_test_chroot -d /tmp/dmgr_test_chroot.img

kvm -m 2G -drive format=raw,file=/tmp/dmgr_test_chroot.img

rm -f /tmp/dmgr_test_chroot.img
