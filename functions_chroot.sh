#!/bin/sh

. ${DMGR_CURRENT_DIR}/functions.sh

_run_in_root_system ()
{
    if [ $# -gt 1 ]; then
        local _CHROOT_DIR="$1"
        shift

        for EXE in "$@"; do
            echo_notify "Copying $(basename ${EXE})"
            cp "$EXE" ${_CHROOT_DIR}/tmp
            echo_notify "Running $(basename ${EXE})"
            if ! chroot "$_CHROOT_DIR" /tmp/$(basename "$EXE"); then
                echo_die 1 "Error while running $EXE"
            fi
            rm ${_CHROOT_DIR}/tmp/$(basename "$EXE")
            echo_notify "$(basename ${EXE}) done\n"
        done
    fi
}

_install_deb_pkg ()
{
    if [ $# -gt 1 ]; then
        local _CHROOT_DIR="$1"
        shift

        mkdir -p ${_CHROOT_DIR}/tmp/pkg_repo/pkg
        cp "$@" ${_CHROOT_DIR}/tmp/pkg_repo/pkg
        _PKG_LIST=""
        for PKG in "$@"; do
            _PKG_NAME="$(basename $PKG | cut -d_ -f1)"
            _PKG_LIST="$_PKG_LIST $_PKG_NAME"
        done
        cd ${_CHROOT_DIR}/tmp/pkg_repo
        apt-ftparchive packages pkg > pkg/Packages
        cd -
        DMGR_ARCHITECTURE="$(chroot $_CHROOT_DIR dpkg --print-architecture)"
        echo "Archive: dmgrtmp\nArchitecture: $DMGR_ARCHITECTURE" > ${_CHROOT_DIR}/tmp/pkg_repo/Release
        echo "deb [trusted=yes] file:///tmp/pkg_repo/ pkg/" > ${_CHROOT_DIR}/etc/apt/sources.list.d/dmgrtmp.list
        chroot $_CHROOT_DIR apt update
        echo_notify "Installing following packages: $_PKG_LIST"
        chroot $_CHROOT_DIR apt --allow-unauthenticated -y install $_PKG_LIST

        rm -rf ${_CHROOT_DIR}/tmp/pkg_repo ${_CHROOT_DIR}/etc/apt/sources.list.d/dmgrtmp.list
    fi
}

check_file_list ()
{
    echo_notify "Checking executables"
    if [ $# -ne 0 ]; then
        for FILE in "$@"; do
            if [ ! -f "$FILE" ]; then
                echo_die 1 "$FILE does not exist"
            fi
        done
    else
        echo_die 1 "No file found."
    fi
    echo_notify "File list check done\n"
}

check_exe_list ()
{
    echo_notify "Checking executables"
    if [ $# -ne 0 ]; then
        for EXE in "$@"; do
            if [ ! -x "$EXE" -o ! -f "$EXE"  ]; then
                echo_die 1 "$EXE is not an executable"
            fi
            echo_notify "$EXE OK"
        done
    else
        echo_die 1 "No executables found."
    fi
    echo_notify "Executable list check done\n"
}

setup_chroot_mountpoint ()
{
    echo_notify "Mount bind proc sys dev dev/pts"
    mount --bind /proc ${1}/proc
    mount --bind /sys  ${1}/sys
    mount --bind /dev ${1}/dev
    mount --bind /dev/pts ${1}/dev/pts
}

unset_chroot_mountpoint ()
{
    echo_notify "Umount bind proc sys dev dev/pts"
    umount -f -l ${1}/dev/pts ${1}/dev ${1}/sys ${1}/proc
}

setup_chroot_operation ()
{
    _CHROOT_PATH="$1"

    echo_notify "Setup chroot environment for (packages) operations in ${_CHROOT_PATH}"

    setup_chroot_mountpoint $_CHROOT_PATH

    echo_notify "Prevent service start with policy-rc.d"
    cat <<EOF > ${_CHROOT_PATH}/usr/sbin/policy-rc.d
#!/bin/sh
exit 101
EOF
    echo_notify "divert ischroot"
    _DIVERT_FILE="/usr/bin/ischroot.tmpor"
    export DEBIAN_FRONTEND=noninteractive
    chroot "$_CHROOT_PATH" dpkg-divert --divert "$_DIVERT_FILE" --rename /usr/bin/ischroot
    chroot "$_CHROOT_PATH" ln -s /bin/true /usr/bin/ischroot
}

unset_chroot_operation ()
{
    _CHROOT_PATH="$1"

    echo_notify "Clean apt files and remove service start bypass with policy-rc.d undivert ischroot"
    chroot "$_CHROOT_PATH" /usr/bin/apt-get clean
    rm -rf ${_CHROOT_PATH}/var/lib/apt/lists/*
    rm -f ${_CHROOT_PATH}/usr/sbin/policy-rc.d
    if [ -f "${_CHROOT_PATH}${_DIVERT_FILE}" ]; then
        rm -f ${_CHROOT_PATH}/usr/bin/ischroot
        chroot "$_CHROOT_PATH" dpkg-divert --rename --remove /usr/bin/ischroot
    fi

    unset_chroot_mountpoint $_CHROOT_PATH

    echo_notify "Chroot environment unset\n"
}

_set_chroot_hostname ()
{
    if [ ! -d "$1" ]; then
        echo_die 1 "Need a chroot directory as first argument."
    fi
    if [ -z "$2" ]; then
        echo_die 1 "Need a hostname as second argument."
    fi
    _CHROOT_DIR="$1"
    _HOSTNAME="$2"
    echo "$_HOSTNAME" > ${_CHROOT_DIR}/etc/hostname

    if grep "127.0.1.1" ${_CHROOT_DIR}/etc/hosts; then
        sed -i "s/127.0.1.1.*/127.0.1.1\t${_HOSTNAME}/" ${_CHROOT_DIR}/etc/hosts
    else
        echo "127.0.1.1\t${_HOSTNAME}\n$(cat ${_CHROOT_DIR}/etc/hosts)" > ${_CHROOT_DIR}/etc/hosts
    fi
}

_handle_debootstrap_params ()
{
    DMGR_GENSYS_SYNOPSIS="\
Usage: $DMGR_NAME $DMGR_CMD_NAME [OPTIONS]
  Generate a debian chroot with deboostrap.

OPTIONS:
  -a, --add-package=<PKG>            Add following debian package to the image
  -C, --apt-cacher=<APT_CACHE_ADDR>  Use an temporary apt cache proxy
  -d <DEST>, --destination <DEST>    Destination file (tar gzip)
  -D, --distribution=<DIST>          Set the distribution
  -e <EXE>, --exec=<EXE>             Run executable into the new system
  -n, --no-default-pkg               Do not install default package (packages
                                     needed for boot)
  -H, --hostname                     Set the default hostname (otherwise
                                     hostname is chroot debi)
  -i, --install-deb                  Add debian file to install
  -p, --password                     See the default root password (otherwise
                                     root password is root)
  -r <REPO_ADDR>, --repo <REPO_ADDR> Modify default repo addr (Unused on rpi generation)
  -s, --sysv                         Use sysv instead of systemd
  -h, --help                         Display this help
"

    OPTS=$(getopt -n "$DMGR_CMD_NAME" -o 'a:C:d:D:e:hH:i:np:r:s' -l 'add-package:,apt-cacher:,destination:,distribution:,exec:,help,hostname:,install-deb:,no-default-pkg,password:,repo:,sysv' -- "$@")
    #Bad arguments
    if [ $? -ne 0 ]; then
        echo_err "Bad arguments.\n"
        exit 2
    fi
    eval set -- "$OPTS";
    while true; do
        case "$1" in
            '-a'|'--add-package')
                shift
                DMGR_ADD_PKG_LIST="$DMGR_ADD_PKG_LIST $1"
                shift
                ;;
            '-C'|'--apt-cacher')
                shift
                DMGR_APT_CACHER="$1"
                shift
                ;;
            '-d'|'--destination')
                shift
                DMGR_CHROOT_DIR="$1"
                shift
                ;;
            '-D'|'--distribution')
                shift
                DMGR_DIST="$1"
                shift
                ;;
            '-e'|'--executable')
                shift
                DMGR_EXE_LIST="$DMGR_EXE_LIST $1"
                shift
                ;;
            '-h'|'--help')
                echo "$DMGR_GENSYS_SYNOPSIS"
                exit 0
                ;;
            '-H'|'--hostname')
                shift
                DMGR_HOSTNAME="$1"
                shift
                ;;
            '-i'|'--install-deb')
                shift
                DMGR_DEB_PKGS="$DMGR_DEB_PKGS $1"
                shift
                ;;
            '-n'|'--no-default-pkg')
                shift
                DMGR_NO_DEFAULT_PKG="on"
                ;;
            '-p'|'--password')
                shift
                DMGR_ROOT_PASSWORD="$1"
                shift
                ;;
            '-r'|'--repo')
                shift
                DMGR_REPO_ADDR="$1"
                shift
                ;;
            '-s'|'--sysv')
                shift
                DMGR_SYSV="ON"
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "$DMGR_GENSYS_SYNOPSIS"
                echo_die 1 "Wrong argument $1"
                ;;
        esac
    done

    if [ $# -ne 0 ]; then
        echo "$DMGR_GENSYS_SYNOPSIS"
        echo_die 1 "To much argument ($*)"
    fi

    if [ -z "$DMGR_CHROOT_DIR" ]; then
        echo "$DMGR_GENSYS_SYNOPSIS"
        echo_die 1 "Destination is mandatory"
    fi

    if [ -e "$DMGR_CHROOT_DIR" ]; then
        echo_die 1 "$DMGR_CHROOT_DIR already exist"
    fi

    if [ -n "$DMGR_EXE_LIST" ]; then
        check_exe_list $DMGR_EXE_LIST
    fi

    if [ -n "$DMGR_DEB_PKGS" ]; then
        check_file_list $DMGR_DEB_PKGS
    fi

    if [ -z "$DMGR_ROOT_PASSWORD" ]; then
        export DMGR_ROOT_PASSWORD="root"
    fi

    if [ -z "$DMGR_HOSTNAME" ]; then
        export DMGR_HOSTNAME="dbmgrsys"
    fi
}

_chroot_add_pkg ()
{
    local _CHROOT_DIR="$1"
    shift

    if [ "$#" -gt 0 ]; then
        chroot $_CHROOT_DIR /usr/bin/apt-get update
        echo_notify "Following packages will be added:\n$*"
        chroot $_CHROOT_DIR /usr/bin/apt-get --allow-unauthenticated -y install $*
    fi
}

DMGR_DEFAULT_BASE_PACKAGES="console-data dosfstools ifupdown iputils-ping isc-dhcp-client kbd less net-tools screen vim wget"

_debootstrap_pc ()
{
    _handle_debootstrap_params "$@"

    mkdir -p $DMGR_CHROOT_DIR
    # The filesystem root directory must let users read and execute
    chmod 755 "$DMGR_CHROOT_DIR"

    if [ -z "$DMGR_DIST" ]; then
        DMGR_DIST=buster
    fi

    echo_notify "Destination: $DMGR_DST"

    if [ -z "$DMGR_REPO_ADDR" ]; then
        DMGR_REPO_ADDR="ftp.debian.org/debian"
    fi

    if [ -n "$DMGR_APT_CACHER" ]; then
        DMGR_DEBOOTSTRAP_URL="http://${DMGR_APT_CACHER}/${DMGR_REPO_ADDR}"
    else
        DMGR_DEBOOTSTRAP_URL="http://${DMGR_REPO_ADDR}"
    fi

    echo_notify "Generating a bootstrap from ${DMGR_DEBOOTSTRAP_URL}."

    if [ "$DMGR_SYSV" = "ON" ]; then
        DMGR_INCLUDE_PKG="locales,sysvinit-core,udev"
    else
        DMGR_INCLUDE_PKG="locales,systemd,systemd-sysv,udev"
    fi
    DMGR_INCLUDE_PKG="${DMGR_INCLUDE_PKG},ntpdate"

    trap_cleanup ()
    {
        unset_chroot_operation $DMGR_CHROOT_DIR
        rm -rf $DMGR_CHROOT_DIR
    }

    set_trap "trap_cleanup"

    if ! debootstrap --arch=amd64 --components="main,contrib,non-free" --include="$DMGR_INCLUDE_PKG" --variant=minbase "$DMGR_DIST" "$DMGR_CHROOT_DIR" "$DMGR_DEBOOTSTRAP_URL"; then
        set +e
        unset_chroot_operation ${DMGR_CHROOT_DIR}
        unset_trap
        echo_die 1 "debootstrap failed."
    fi

    setup_chroot_operation ${DMGR_CHROOT_DIR}

    _set_chroot_hostname $DMGR_CHROOT_DIR $DMGR_HOSTNAME

    cat <<EOF > ${DMGR_CHROOT_DIR}/etc/default/locale
LANG="C"
LANGUAGE="C"
EOF

    if [ -z "$DMGR_NO_DEFAULT_PKG" ]; then
        chroot "$DMGR_CHROOT_DIR" /usr/bin/apt-get update
        chroot "$DMGR_CHROOT_DIR" /usr/bin/apt-get --allow-unauthenticated -y upgrade
        chroot "$DMGR_CHROOT_DIR" /usr/bin/apt-get --allow-unauthenticated -y install linux-image-amd64 $DMGR_DEFAULT_BASE_PACKAGES
    fi

    echo "root:${DMGR_ROOT_PASSWORD}" | chroot "$DMGR_CHROOT_DIR" /usr/sbin/chpasswd

    _chroot_add_pkg $DMGR_CHROOT_DIR $DMGR_ADD_PKG_LIST
    _install_deb_pkg $DMGR_CHROOT_DIR $DMGR_DEB_PKGS
    _run_in_root_system $DMGR_CHROOT_DIR $DMGR_EXE_LIST

    unset_chroot_operation "$DMGR_CHROOT_DIR"

    unset_trap

    if [ -n "$DMGR_APT_CACHER" ]; then
        cat <<EOF > ${DMGR_CHROOT_DIR}/etc/apt/sources.list
deb http://${DMGR_REPO_ADDR} $DMGR_DIST main contrib non-free
EOF
    fi
}

_debootstrap_rpi ()
{
    _handle_debootstrap_params "$@"

    mkdir -p $DMGR_CHROOT_DIR
    # The filesystem root directory must let users read and execute
    chmod 755 "$DMGR_CHROOT_DIR"

    if [ ! -d "$DMGR_CHROOT_DIR" ]; then
        echo_die 1 "Can not find a directory at '$DMGR_CHROOT_DIR'"
    fi

    if [ -z "$DMGR_DIST" ]; then
        DMGR_DIST=buster
    fi

    echo_notify "Destination: $DMGR_DST"

    DMGR_RASPBIAN_URL="archive.raspbian.org/raspbian"
    DMGR_RASPBERRYPI_URL="archive.raspberrypi.org/debian"

    if [ -n "$DMGR_APT_CACHER" ]; then
        DMGR_DEBOOTSTRAP_URL="http://${DMGR_APT_CACHER}/${DMGR_RASPBIAN_URL}"
    else
        DMGR_DEBOOTSTRAP_URL="http://${DMGR_RASPBIAN_URL}"
    fi

    echo_notify "Generating a bootstrap from ${DMGR_DEBOOTSTRAP_URL}."

    if [ "$DMGR_SYSV" = "ON" ]; then
        DMGR_INCLUDE_PKG="locales,sysvinit-core,udev"
    else
        DMGR_INCLUDE_PKG="locales,systemd,systemd-sysv,udev"
    fi

    DMGR_INCLUDE_PKG="${DMGR_INCLUDE_PKG},ntpdate"

    trap_cleanup ()
    {
        kill $(pidof qemu-arm-static) 1> /dev/null 2>&1
        unset_chroot_operation ${DMGR_CHROOT_DIR}
        rm -rf $DMGR_CHROOT_DIR
    }

    set_trap "trap_cleanup"

    if ! debootstrap --arch=armhf --components="main,contrib,non-free,rpi" --include="$DMGR_INCLUDE_PKG" --no-check-gpg --variant=minbase "$DMGR_DIST" "$DMGR_CHROOT_DIR" "$DMGR_DEBOOTSTRAP_URL"; then
        set +e
        trap_cleanup
        unset_trap
        echo_die 1 "debootstrap failed."
    fi

    setup_chroot_operation ${DMGR_CHROOT_DIR}

    _set_chroot_hostname $DMGR_CHROOT_DIR $DMGR_HOSTNAME

    cat <<EOF > ${DMGR_CHROOT_DIR}/etc/default/locale
LANG="C"
LANGUAGE="C"
EOF

    wget -q https://${DMGR_RASPBIAN_URL}.public.key -O -            | chroot "$DMGR_CHROOT_DIR" apt-key add -
    wget -q http://${DMGR_RASPBERRYPI_URL}/raspberrypi.gpg.key -O - | chroot "$DMGR_CHROOT_DIR" apt-key add -

    if [ -n "$DMGR_APT_CACHER" ]; then
        cat <<EOF > ${DMGR_CHROOT_DIR}/etc/apt/sources.list
deb http://${DMGR_APT_CACHER}/${DMGR_RASPBIAN_URL} $DMGR_DIST main contrib firmware non-free rpi
deb http://${DMGR_APT_CACHER}/${DMGR_RASPBERRYPI_URL} $DMGR_DIST main ui untested
EOF
    else
        cat <<EOF > ${DMGR_CHROOT_DIR}/etc/apt/sources.list
deb http://${DMGR_RASPBIAN_URL} $DMGR_DIST main contrib firmware non-free rpi
deb http://${DMGR_RASPBERRYPI_URL} $DMGR_DIST main ui untested
EOF
    fi

    cat <<EOF > ${DMGR_CHROOT_DIR}/etc/udev/rules.d/10-gbr-vchiq-permissions.rules
SUBSYSTEM=="rpivid-*",GROUP="video",MODE="0660"
EOF

    if [ -z "$DMGR_NO_DEFAULT_PKG" ]; then
        chroot "$DMGR_CHROOT_DIR" /usr/bin/apt-get update
        chroot "$DMGR_CHROOT_DIR" /usr/bin/apt-get --allow-unauthenticated -y upgrade
        # Tmp caution with "raspi-copies-and-fills" and qemu-user-static version
        chroot "$DMGR_CHROOT_DIR" /usr/bin/apt-get --allow-unauthenticated -y install firmware-brcm80211 raspberrypi-bootloader raspberrypi-kernel raspi-copies-and-fills wpasupplicant $DMGR_DEFAULT_BASE_PACKAGES
    fi

    echo "root:${DMGR_ROOT_PASSWORD}" | chroot "$DMGR_CHROOT_DIR" /usr/sbin/chpasswd

    _chroot_add_pkg $DMGR_CHROOT_DIR $DMGR_ADD_PKG_LIST
    _install_deb_pkg $DMGR_CHROOT_DIR $DMGR_DEB_PKGS
    _run_in_root_system $DMGR_CHROOT_DIR $DMGR_EXE_LIST

    unset_chroot_operation "$DMGR_CHROOT_DIR"

    unset_trap

    if [ -n "$DMGR_APT_CACHER" ]; then
        cat <<EOF > ${DMGR_CHROOT_DIR}/etc/apt/sources.list
deb http://${DMGR_RASPBIAN_URL} $DMGR_DIST main contrib firmware non-free rpi
deb http://${DMGR_RASPBERRYPI_URL} $DMGR_DIST main ui untested
EOF
    fi
}

_chroot_exec ()
{
    DMGR_CHROOT_EXEC_SYNOPSIS="\
Usage: chroot-exec $DMGR_CMD_NAME [OPTIONS]
  Exec script or install package in a chroot preventing service running.

OPTIONS:
  -a, --add-package=<PKG>         Add following debian package
  -d <DEST>, --destination <DEST> Destination file (tar gzip)
  -e, --exec=<EXE>                Run executable
  -h, --help                      Display this help
"

    OPTS=$(getopt -n chroot-exec -o 'a:d:e:h' -l 'add-package:,destination:,exec:,help' -- "$@")
    #Bad arguments
    if [ $? -ne 0 ]; then
        echo_err "Bad arguments.\n"
        exit 2
    fi
    eval set -- "$OPTS";
    while true; do
        case "$1" in
            '-a'|'--add-package')
                shift
                DMGR_ADD_PKG_LIST="$DMGR_ADD_PKG_LIST $1"
                shift
                ;;

            '-d'|'--destination')
                shift
                DMGR_CHROOT_DIR="$1"
                shift
                ;;

            '-e'|'--executable')
                shift
                DMGR_EXE_LIST="$DMGR_EXE_LIST $1"
                shift
                ;;

            '-h'|'--help')
                shift
                echo "$DMGR_CHROOT_EXEC_SYNOPSIS"
                exit 0
                ;;

            --)
                shift
                break
                ;;

            *)
                echo "$DMGR_CHROOT_EXEC_SYNOPSIS"
                echo_die 1 "Unknown argument $1"
                ;;
        esac
    done

    if [ $# -ne 0 ]; then
        echo "$DMGR_CHROOT_EXEC_SYNOPSIS"
        echo_die 1 "To much argument ($*)"
    fi

    if [ ! -d "$DMGR_CHROOT_DIR" ]; then
        echo_die 1 "Need a destination directory"
    fi

    if [ -n "$DMGR_EXE_LIST" -o -n "$DMGR_DEB_PKGS" -o -n "$DMGR_ADD_PKG_LIST" ]; then
        set_trap "unset_chroot_operation $DMGR_CHROOT_DIR"
        setup_chroot_operation "$DMGR_CHROOT_DIR"

        _chroot_add_pkg $DMGR_CHROOT_DIR $DMGR_ADD_PKG_LIST
        _install_deb_pkg $DMGR_CHROOT_DIR $DMGR_DEB_PKGS
        _run_in_root_system $DMGR_CHROOT_DIR $DMGR_EXE_LIST

        unset_chroot_operation "$DMGR_CHROOT_DIR"
        unset_trap
    fi
}

_chroot ()
{
    DMGR_CHROOT_SYNOPSIS="\
Usage: $DMGR_NAME $DMGR_CMD_NAME <CHROOT_DIR>
  Chroot preventing service running.
"

    DMGR_CHROOT_DIR="$1"
    shift

    if [ ! -d "$DMGR_CHROOT_DIR" ]; then
        echo "$DMGR_CHROOT_SYNOPSIS"
        echo_die 1 "Need a destination directory"
    fi

    set_trap "unset_chroot_operation $DMGR_CHROOT_DIR"
    setup_chroot_operation "$DMGR_CHROOT_DIR"

    chroot "$DMGR_CHROOT_DIR" "$@"

    unset_chroot_operation "$DMGR_CHROOT_DIR"
    unset_trap

}

_chroot_to_livesys_dir ()
{
    if [ 2 -ne "$#" ]; then
        echo "$DMGR_LIVESYS_SYNOPSIS"
        echo_die 1 "rpi_dir_to_img need 2 arguments."
    fi
    if [ ! -d "$1" -o ! -d "$2" ]; then
        echo "$DMGR_LIVESYS_SYNOPSIS"
        echo_die 1 "Need a directories as arguments"
    fi

    echo_notify "Generating live directory in $DMGR_DST_PATH"

    echo_notify "Copying chroot $1 to $2 build directory ..."
    mkdir -p ${2}/tmpdir
    rsync -ad ${1}/* ${2}/tmpdir/
    echo_notify "Copy done"

    echo_notify "Generating live-boot initrd and filesquahfs ..."

    if [ "$DMGR_TYPE" = "RPI" ]; then
        # Hack for raspbian kernel version handling
        INITRAMFS_GEN_SH=$(mktemp --suffix=_initramfs_gen.sh)
        set_trap "unset_chroot_operation ${2}/tmpdir; rm -rf INITRAMFS_GEN_SH"
        setup_chroot_operation ${2}/tmpdir
        cat <<EOF > $INITRAMFS_GEN_SH
#!/bin/sh -ex

for kversion in \$(ls /lib/modules); do
    mkinitramfs -o /boot/initrd-\${kversion}.img \$kversion
done
EOF
        chmod +x $INITRAMFS_GEN_SH
        _chroot_add_pkg ${2}/tmpdir live-boot
        _run_in_root_system ${2}/tmpdir $INITRAMFS_GEN_SH
        rm -f $INITRAMFS_GEN_SH
        unset_chroot_operation ${2}/tmpdir
        unset_trap
    else
        set_trap "unset_chroot_operation ${2}/tmpdir"
        setup_chroot_operation ${2}/tmpdir
        _chroot_add_pkg  ${2}/tmpdir live-boot
        # live-boot installation automatically run update-initramfs
        unset_chroot_operation ${2}/tmpdir
        unset_trap
    fi

    if [ -n "$DMGR_PERSISTENCE_PATHS" ]; then
        mkdir ${2}/persistence
        for ppath in $DMGR_PERSISTENCE_PATHS; do
            mv ${2}/tmpdir${ppath} ${2}/persistence
            echo "$ppath source=persistence/$(basename $ppath)" >> ${2}/persistence.conf
        done
    fi

    if [ -n "$DMGR_ADD_PKG_LIST" -o -n "$DMGR_DEB_PKGS" -o -n "$DMGR_EXE_LIST" ]; then
        setup_chroot_operation ${2}/tmpdir
        _chroot_add_pkg ${2}/tmpdir $DMGR_ADD_PKG_LIST
        _install_deb_pkg $DMGR_CHROOT_DIR $DMGR_DEB_PKGS
        _run_in_root_system ${2}/tmpdir $DMGR_EXE_LIST
        unset_chroot_operation ${2}/tmpdir
    fi

    mv ${2}/tmpdir/boot/* ${2}/

    mkdir ${2}/live
    mksquashfs ${2}/tmpdir ${2}/live/filesystem.squashfs
    rm -rf ${2}/tmpdir
}

_handle_dir_to_livesys_args ()
{
    DMGR_LIVESYS_SYNOPSIS="\
Usage: $DMGR_NAME $DMGR_CMD_NAME [OPTIONS]
  Convert a chroot to a live system an flash it to a block device or a file.

OPTIONS:
  -a <PKG>, --add-package=<PKG> Add following debian package to the image
  -d <DST>, --destination <DST> Destination path
  -e <EXE>, --exec=<EXE>        Run executable into the new system
  -h, --help                    Display this help
  -i, --install-deb                  Add debian file to install
  -s <SRC>, --source=<SRC>      Source chroot directory
  -p, --add-persistence=PATH    Add persistency on specified path
"

    OPTS=$(getopt -n "$DMGR_CMD_NAME" -o 'a:d:e:hi:p:s:' -l 'add-package:,destination:,exec:,help,install-deb:,source:,add-persistence:' -- "$@")
    #Bad arguments
    if [ $? -ne 0 ]; then
        echo_err "Bad arguments.\n"
        exit 2
    fi
    eval set -- "$OPTS";
    while true; do
        case "$1" in
            '-a'|'--add-package')
                shift
                DMGR_ADD_PKG_LIST="$DMGR_ADD_PKG_LIST $1"
                shift
                ;;
            '-d'|'--destination')
                shift
                DMGR_DST_PATH="$1"
                shift
                ;;
            '-e'|'--executable')
                shift
                DMGR_EXE_LIST="$DMGR_EXE_LIST $1"
                shift
                ;;
            '-h'|'--help')
                echo "$DMGR_LIVESYS_SYNOPSIS"
                exit 0
                ;;
            '-i'|'--install-deb')
                shift
                DMGR_DEB_PKGS="$DMGR_DEB_PKGS $1"
                shift
                ;;
            '-p'|'--add-persistence')
                shift
                DMGR_PERSISTENCE_PATHS="$DMGR_PERSISTENCE_PATHS $1"
                shift
                ;;
            '-s'|'--source')
                shift
                DMGR_SRC_PATH="$1"
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "$DMGR_LIVESYS_SYNOPSIS"
                echo_die 1 "Wrong argument $1"
                ;;
        esac
    done

    if [ -z "$DMGR_DST_PATH" ]; then
        echo "$DMGR_LIVESYS_SYNOPSIS"
        echo_die 1 "Destination is mandatory"
    fi

    if [ ! -d "$DMGR_SRC_PATH" ]; then
        echo "$DMGR_LIVESYS_SYNOPSIS"
        echo_die 1 "$DMGR_SRC_PATH chroot source directory does not exist"
    fi
}

_chroot_to_live_squashfs ()
{
    _handle_dir_to_livesys_args "$@"

    if [ -e "$DMGR_DST_PATH" ]; then
        echo_die 1 "Destination already exist"
    fi

    DMGR_TMP_DIR="$(mktemp -d --suffix=_dmgr_tmp_dir)"
    DMGR_EXCLUSION_FILE="$(mktemp --suffix=_dmgr_exclusion)"
    set_trap "unset_chroot_operation $DMGR_TMP_DIR; rm -rf $DMGR_EXCLUSION_FILE $DMGR_TMP_DIR"

    echo_notify "Copying chroot directory ..."
    rsync -ad ${DMGR_SRC_PATH}/* ${DMGR_TMP_DIR}/
    echo_notify "Copy done."

    setup_chroot_operation $DMGR_TMP_DIR
    _chroot_add_pkg $DMGR_TMP_DIR live-boot
    _chroot_add_pkg $DMGR_TMP_DIR $DMGR_ADD_PKG_LIST
    _install_deb_pkg $DMGR_TMP_DIR $DMGR_DEB_PKGS
    _run_in_root_system $DMGR_TMP_DIR $DMGR_EXE_LIST
    unset_chroot_operation $DMGR_TMP_DIR

    rm -rf ${DMGR_TMP_DIR}/boot
    for pers_path in $DMGR_PERSISTENCE_PATHS; do
        rm -rf ${DMGR_TMP_DIR}${pers_path}
    done

    mksquashfs $DMGR_TMP_DIR $DMGR_DST_PATH

    unset_trap
    rm -rf $DMGR_EXCLUSION_FILE $DMGR_TMP_DIR
}
