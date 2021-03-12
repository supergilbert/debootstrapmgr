#!/bin/sh

. ${DMGR_CURRENT_DIR}/functions.sh

run_in_root_system ()
{
    local ROOT_DIR="$1"
    shift

    if [ $# -ne 0 ]; then
        for EXE in "$@"; do
            echo_notify "Copying $(basename ${EXE})"
            cp "$EXE" ${ROOT_DIR}/tmp
            echo_notify "Running $(basename ${EXE})"
            if ! chroot "$ROOT_DIR" /tmp/$(basename "$EXE"); then
                cleanup_n_die 1 "Error while running $EXE"
            fi
            rm ${ROOT_DIR}/tmp/$(basename "$EXE")
            echo_notify "$(basename ${EXE}) done\n"
        done
    fi
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
    echo_notify "Executables check done\n"
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
    DIVERT_FILE="/usr/bin/ischroot.tmpor"
    export DEBIAN_FRONTEND=noninteractive
    chroot "$_CHROOT_PATH" dpkg-divert --divert "$DIVERT_FILE" --rename /usr/bin/ischroot
    chroot "$_CHROOT_PATH" ln -s /bin/true /usr/bin/ischroot

    DEBIANATOR_RUNNING="YES"
}

unset_chroot_operation ()
{
    _CHROOT_PATH="$1"

    DEBIANATOR_RUNNING=""

    echo_notify "Clean apt files ane remove service start bypass with policy-rc.d undivert ischroot"
    chroot "$_CHROOT_PATH" /usr/bin/apt-get clean
    rm -rf ${_CHROOT_PATH}/var/lib/apt/lists/*
    rm -f ${_CHROOT_PATH}/usr/sbin/policy-rc.d
    if [ -f "${_CHROOT_PATH}${DIVERT_FILE}" ]; then
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

wait_blk_path ()
{
    # Take the block device and the partition number as argument.
    # Then check for available correspondance. (Need set -e)
    local DMGR_BLK_REALPATH="$(realpath $1)"
    if [ -z "$DMGR_BLK_REALPATH" ]; then
        echo_die 1 "Block device path argument not set."
    fi
    if [ -z "$2" ]; then
        echo_die 1 "Partition number argument not set."
    fi
    partprobe $1
    TRY_NUMBER=10
    for count in $(seq $TRY_NUMBER -1 0); do
        if   [ -b "${DMGR_BLK_REALPATH}${2}" ]; then
            echo -n "${DMGR_BLK_REALPATH}${2}"
            return 0
        elif [ -b "${DMGR_BLK_REALPATH}p${2}" ]; then
            echo -n "${DMGR_BLK_REALPATH}p${2}"
            return 0
        fi
        sleep 1
    done
    return 1
}

_handle_debootstrap_params ()
{
    DMGR_GENSYS_SYNOPSIS="\
Usage: $DMGR_NAME $DMGR_CMD_NAME [OPTIONS]
  Generate a RPI Image.

OPTIONS:
  -a, --add-package=<PKG>           Add following package to the image
  -C, --apt-cacher=<APT_CACHE_ADDR> Use an apt cache proxy
  -d <DEST>, --destination <DEST>   Destination file (tar gzip)
  -D, --distribution=<DIST>         Set the distribution
  -e, --exec=<EXE>                  Multiple call of this option will add
                                    executables to run during generation
  -n, --no-default-pkg              Do not install default package (packages
                                    needed for boot)
  -H, --hostname                    Set the default hostname (otherwise
                                    hostname is chroot debi)
  -p, --password                    See the default root password (otherwise
                                    root password is root)
  -s, --sysv                        Use sysv instead of systemd
  -h, --help                        Display this help
"

    OPTS=$(getopt -n "$DMGR_CMD_NAME" -o 'a:C:d:D:e:hH:np:s' -l 'add-package:,apt-cacher:,destination:,distribution:,exec:,help,hostname:,no-default-pkg,password:,sysv' -- "$@")
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
            '-n'|'--no-default-pkg')
                shift
                DMGR_NO_DEFAULT_PKG="on"
                ;;
            '-p'|'--password')
                shift
                DMGR_ROOT_PASSWORD="$1"
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

    if [ -z "$DMGR_ROOT_PASSWORD" ]; then
        export DMGR_ROOT_PASSWORD="root"
    fi

    if [ -z "$DMGR_HOSTNAME" ]; then
        export DMGR_HOSTNAME="debi"
    fi
}

_chroot_add_pkg_n_run_exe ()
{
    local _CHROOT_DIR="$1"

    chroot $_CHROOT_DIR /usr/bin/apt-get update
    if [ -n "$DMGR_ADD_PKG_LIST" ]; then
        echo_notify "Following packages will be added:\n${DMGR_ADD_PKG_LIST}"
        chroot ${_CHROOT_DIR} /usr/bin/apt-get --allow-unauthenticated -y install $DMGR_ADD_PKG_LIST
    fi

    if [ -n "$DMGR_EXE_LIST" ]; then
        echo_notify "Executing: $DMGR_EXE_LIST"
        run_in_root_system "$_CHROOT_DIR" $DMGR_EXE_LIST
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

    DMGR_DEBIAN_URL="ftp.debian.org/debian"

    if [ -n "$DMGR_APT_CACHER" ]; then
        DMGR_DEBOOTSTRAP_URL="http://${DMGR_APT_CACHER}/${DMGR_DEBIAN_URL}"
    else
        DMGR_DEBOOTSTRAP_URL="http://${DMGR_DEBIAN_URL}"
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

    if ! debootstrap --components="main,contrib,non-free" --include="$DMGR_INCLUDE_PKG" --arch=amd64 --variant=minbase "$DMGR_DIST" "$DMGR_CHROOT_DIR" "$DMGR_DEBOOTSTRAP_URL"; then
        set +e
        unset_chroot_operation ${DMGR_CHROOT_DIR}
        unset_trap
        echo_die 1 "qemu-debootstrap failed."
    fi

    setup_chroot_operation ${DMGR_CHROOT_DIR}

    _set_chroot_hostname $DMGR_CHROOT_DIR $DMGR_HOSTNAME

    cat <<EOF > ${DMGR_CHROOT_DIR}/etc/default/locale
LANG="C"
LANGUAGE="C"
EOF

    if [ -n "$DMGR_APT_CACHER" ]; then
        cat <<EOF > ${DMGR_CHROOT_DIR}/etc/apt/sources.list
deb http://${DMGR_APT_CACHER}/${DMGR_DEBIAN_URL} $DMGR_DIST main contrib non-free
EOF
    else
        cat <<EOF > ${DMGR_CHROOT_DIR}/etc/apt/sources.list
deb http://${DMGR_DEBIAN_URL} $DMGR_DIST main contrib non-free
EOF
    fi

    if [ -z "$DMGR_NO_DEFAULT_PKG" ]; then
        chroot "$DMGR_CHROOT_DIR" /usr/bin/apt-get update
        chroot "$DMGR_CHROOT_DIR" /usr/bin/apt-get --allow-unauthenticated -y upgrade
        chroot "$DMGR_CHROOT_DIR" /usr/bin/apt-get --allow-unauthenticated -y install linux-image-amd64 $DMGR_DEFAULT_BASE_PACKAGES
    fi

    echo "root:${DMGR_ROOT_PASSWORD}" | chroot "$DMGR_CHROOT_DIR" /usr/sbin/chpasswd

    _chroot_add_pkg_n_run_exe "$DMGR_CHROOT_DIR"

    unset_chroot_operation "$DMGR_CHROOT_DIR"

    unset_trap

    if [ -n "$DMGR_APT_CACHER" ]; then
        cat <<EOF > ${DMGR_CHROOT_DIR}/etc/apt/sources.list
deb http://${DMGR_DEBIAN_URL} $DMGR_DIST main contrib non-free
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
    }

    set_trap "trap_cleanup"

    if ! qemu-debootstrap --components="main,contrib,non-free,rpi" --include="$DMGR_INCLUDE_PKG" --no-check-gpg --arch=armhf --variant=minbase "$DMGR_DIST" "$DMGR_CHROOT_DIR" "$DMGR_DEBOOTSTRAP_URL"; then
        set +e
        trap_cleanup
        unset_trap
        echo_die 1 "qemu-debootstrap failed."
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

    _chroot_add_pkg_n_run_exe "$DMGR_CHROOT_DIR"

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
  -a, --add-package=<PKG>           Add following package to the image
  -d <DEST>, --destination <DEST>   Destination file (tar gzip)
  -e, --exec=<EXE>                  Multiple call of this option will add
                                    executables to run during generation
  -h, --help                        Display this help
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

    if [ -n "$DMGR_EXE_LIST" -o -n "$DMGR_ADD_PKG_LIST" ]; then
        set_trap "unset_chroot_operation $DMGR_CHROOT_DIR"
        setup_chroot_operation "$DMGR_CHROOT_DIR"

        _chroot_add_pkg_n_run_exe "$DMGR_CHROOT_DIR"

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
