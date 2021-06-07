. ${DEBG_CURRENT_DIR}/functions.sh

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
        cd ${_CHROOT_DIR}/tmp/pkg_repo
        apt-ftparchive packages pkg > pkg/Packages
        cd -
        DEBG_CHROOT_ARCH="$(chroot $_CHROOT_DIR dpkg --print-architecture)"
        echo "Archive: debgtmp\nArchitecture: $DEBG_CHROOT_ARCH" > ${_CHROOT_DIR}/tmp/pkg_repo/Release
        echo "deb [trusted=yes] file:///tmp/pkg_repo/ pkg/" > ${_CHROOT_DIR}/etc/apt/sources.list.d/debgtmp.list
        cat <<EOF > ${_CHROOT_DIR}/etc/apt/preferences.d/debgtmp.pref
Package: *
Pin: origin ""
Pin-Priority: 1001
EOF

        _PKG_LIST=""
        for PKG in "$@"; do
            _PKG_NAME="$(basename $PKG | cut -d_ -f1)"
            _PKG_LIST="$_PKG_LIST $_PKG_NAME"
        done
        chroot $_CHROOT_DIR apt update
        echo_notify "Installing following packages:${_PKG_LIST}"
        chroot $_CHROOT_DIR apt --allow-unauthenticated -y reinstall $_PKG_LIST

        rm -rf ${_CHROOT_DIR}/etc/apt/preferences.d/debgtmp.pref ${_CHROOT_DIR}/etc/apt/sources.list.d/debgtmp.list ${_CHROOT_DIR}/tmp/pkg_repo
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

    cp -f /etc/resolv.conf  ${_CHROOT_PATH}/etc/resolv.conf

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

    echo > ${_CHROOT_PATH}/etc/resolv.conf

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
    DEBG_GENSYS_SYNOPSIS="\
Usage: $DEBG_NAME $DEBG_CMD_NAME [OPTIONS]
  Generate a debian chroot with deboostrap.

OPTIONS:
  -A --architecture                  Set the target architecture
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
  -r <REPO_FILE>, --repo <REPO_FILE> Modify default apt repositories with the
                                     provided sources.list file. (Use the first
                                     line entry for debootstrap)
  -s, --sysv                         Use sysv instead of systemd
  -h, --help                         Display this help
"

    OPTS=$(getopt -n "$DEBG_CMD_NAME" -o 'A:a:C:d:D:e:hH:i:np:r:s' -l 'architecture:,add-package:,apt-cacher:,destination:,distribution:,exec:,help,hostname:,install-deb:,no-default-pkg,password:,repo:,sysv' -- "$@")
    #Bad arguments
    if [ $? -ne 0 ]; then
        echo_err "Bad arguments.\n"
        exit 2
    fi
    eval set -- "$OPTS";
    while true; do
        case "$1" in
            '-A'|'--architecture')
                shift
                DEBG_TARGET_ARCH="$1"
                shift
                ;;
            '-a'|'--add-package')
                shift
                DEBG_ADD_PKG_LIST="$DEBG_ADD_PKG_LIST $1"
                shift
                ;;
            '-C'|'--apt-cacher')
                shift
                DEBG_APT_CACHER="$1"
                shift
                ;;
            '-d'|'--destination')
                shift
                DEBG_CHROOT_DIR="$1"
                if [ -z "$DEBG_CHROOT_DIR" ]; then
                    echo "$DEBG_GENSYS_SYNOPSIS"
                    echo_die 1 "Destination is mandatory"
                fi
                if [ -e "$DEBG_CHROOT_DIR" ]; then
                    echo_die 1 "$DEBG_CHROOT_DIR already exist"
                fi
                shift
                ;;
            '-D'|'--distribution')
                shift
                DEBG_DIST="$1"
                shift
                ;;
            '-e'|'--executable')
                shift
                DEBG_EXE_LIST="$DEBG_EXE_LIST $1"
                shift
                ;;
            '-h'|'--help')
                echo "$DEBG_GENSYS_SYNOPSIS"
                exit 0
                ;;
            '-H'|'--hostname')
                shift
                DEBG_HOSTNAME="$1"
                shift
                ;;
            '-i'|'--install-deb')
                shift
                DEBG_DEB_PKGS="$DEBG_DEB_PKGS $1"
                shift
                ;;
            '-n'|'--no-default-pkg')
                shift
                DEBG_NO_DEFAULT_PKG="on"
                ;;
            '-p'|'--password')
                shift
                DEBG_ROOT_PASSWORD="$1"
                shift
                ;;
            '-r'|'--repo')
                shift
                DEBG_REPO_FILE="$1"
                if [ ! -r "$DEBG_REPO_FILE" ]; then
                    echo_die 1 "$DEBG_REPO_FILE repository file is unreadable"
                fi
                shift
                ;;
            '-s'|'--sysv')
                shift
                DEBG_SYSV="ON"
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "$DEBG_GENSYS_SYNOPSIS"
                echo_die 1 "Wrong argument $1"
                ;;
        esac
    done

    if [ $# -ne 0 ]; then
        echo "$DEBG_GENSYS_SYNOPSIS"
        echo_die 1 "To much argument ($*)"
    fi

    if [ -n "$DEBG_EXE_LIST" ]; then
        check_exe_list $DEBG_EXE_LIST
    fi

    if [ -n "$DEBG_DEB_PKGS" ]; then
        check_file_list $DEBG_DEB_PKGS
    fi

    if [ -z "$DEBG_ROOT_PASSWORD" ]; then
        export DEBG_ROOT_PASSWORD="root"
    fi

    if [ -z "$DEBG_HOSTNAME" ]; then
        export DEBG_HOSTNAME="dbmgrsys"
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

DEBG_DEFAULT_BASE_PACKAGES="console-data dosfstools ifupdown iputils-ping isc-dhcp-client kbd less net-tools screen vim wget"

_debootstrap_pc ()
{
    _handle_debootstrap_params "$@"

    if [ -z "$DEBG_TARGET_ARCH" ]; then
        DEBG_TARGET_ARCH=amd64
    fi

    mkdir -p $DEBG_CHROOT_DIR
    # The filesystem root directory must let users read and execute
    chmod 755 "$DEBG_CHROOT_DIR"

    echo_notify "Destination: $DEBG_DST"

    echo_notify "Generating a bootstrap from ${DEBG_DEBOOTSTRAP_URL}."

    if [ "$DEBG_SYSV" = "ON" ]; then
        DEBG_INCLUDE_PKG="locales,sysvinit-core,udev"
    else
        DEBG_INCLUDE_PKG="locales,systemd,systemd-sysv,udev"
    fi
    DEBG_INCLUDE_PKG="${DEBG_INCLUDE_PKG},ntpdate"

    trap_cleanup ()
    {
        unset_chroot_operation $DEBG_CHROOT_DIR
        rm -rf $DEBG_CHROOT_DIR
    }

    set_trap "trap_cleanup"

    if [ -n "$DEBG_REPO_FILE" ]; then
        DEBG_REPO_URI="$(${DEBG_CURRENT_DIR}/get_aptsources_entry_data.py $DEBG_REPO_FILE 0 uri)"
        DEBG_REPO_CMP="$(${DEBG_CURRENT_DIR}/get_aptsources_entry_data.py $DEBG_REPO_FILE 0 components)"
        DEBG_DIST="$(${DEBG_CURRENT_DIR}/get_aptsources_entry_data.py $DEBG_REPO_FILE 0 suite)"
    else
        DEBG_REPO_URI="http://ftp.debian.org/debian"
        DEBG_REPO_CMP="main,contrib,non-free"
        DEBG_DIST="buster"
    fi

    if [ -n "$DEBG_APT_CACHER" ]; then
        DEBG_REPO_URI=$(echo $DEBG_REPO_URI | sed "s#\(http://\)\(.*\)#\1${DEBG_APT_CACHER}/\2#g")
    else
        DEBG_REPO_URI="$DEBG_REPO_URI"
    fi

    if ! debootstrap --arch="$DEBG_TARGET_ARCH" --components="$DEBG_REPO_CMP" --include="$DEBG_INCLUDE_PKG" --variant=minbase "$DEBG_DIST" "$DEBG_CHROOT_DIR" "$DEBG_REPO_URI"; then
        set +e
        unset_chroot_operation ${DEBG_CHROOT_DIR}
        unset_trap
        echo_die 1 "debootstrap failed."
    fi

    if [ -n "$DEBG_REPO_FILE" ]; then
        cp $DEBG_REPO_FILE ${DEBG_CHROOT_DIR}/etc/apt/sources.list
    fi

    if [ -n "$DEBG_APT_CACHER" ]; then
        echo "Acquire::http { Proxy \"http://${DEBG_APT_CACHER}\"; };" > ${DEBG_CHROOT_DIR}/etc/apt/apt.conf.d/99debgentmp
    fi

    setup_chroot_operation ${DEBG_CHROOT_DIR}

    _set_chroot_hostname $DEBG_CHROOT_DIR $DEBG_HOSTNAME

    cat <<EOF > ${DEBG_CHROOT_DIR}/etc/default/locale
LANG="C"
LANGUAGE="C"
EOF

    case "$DEBG_TARGET_ARCH" in
        "amd64")
            DEBG_KERNEL_PKG=linux-image-amd64
            shift
            ;;
        "i386")
            DEBG_KERNEL_PKG=linux-image-686
            shift
            ;;
        *)
            DEBG_KERNEL_PKG=linux-image-generic
            shift
            ;;
    esac

    if [ -z "$DEBG_NO_DEFAULT_PKG" ]; then
        chroot "$DEBG_CHROOT_DIR" /usr/bin/apt-get update
        chroot "$DEBG_CHROOT_DIR" /usr/bin/apt-get --allow-unauthenticated -y upgrade
        chroot "$DEBG_CHROOT_DIR" /usr/bin/apt-get --allow-unauthenticated -y install $DEBG_KERNEL_PKG $DEBG_DEFAULT_BASE_PACKAGES
    fi

    echo "root:${DEBG_ROOT_PASSWORD}" | chroot "$DEBG_CHROOT_DIR" /usr/sbin/chpasswd

    _chroot_add_pkg $DEBG_CHROOT_DIR $DEBG_ADD_PKG_LIST
    _install_deb_pkg $DEBG_CHROOT_DIR $DEBG_DEB_PKGS
    _run_in_root_system $DEBG_CHROOT_DIR $DEBG_EXE_LIST

    unset_chroot_operation "$DEBG_CHROOT_DIR"

    unset_trap

    if [ -n "$DEBG_APT_CACHER" ]; then
        rm -f ${DEBG_CHROOT_DIR}/etc/apt/apt.conf.d/99debgentmp
    fi
}

_debootstrap_rpi ()
{
    _handle_debootstrap_params "$@"

    if [ -z "$DEBG_TARGET_ARCH" ]; then
        DEBG_TARGET_ARCH=armhf
    else
        if [ "$DEBG_TARGET_ARCH" != "armhf" ]; then
            echo_die 1 "rpi creation support only one architecture (armhf)"
        fi
    fi

    mkdir -p $DEBG_CHROOT_DIR
    # The filesystem root directory must let users read and execute
    chmod 755 "$DEBG_CHROOT_DIR"

    if [ ! -d "$DEBG_CHROOT_DIR" ]; then
        echo_die 1 "Can not find a directory at '$DEBG_CHROOT_DIR'"
    fi

    if [ -z "$DEBG_DIST" ]; then
        DEBG_DIST=buster
    fi

    echo_notify "Destination: $DEBG_DST"

    DEBG_RASPBIAN_URL="archive.raspbian.org/raspbian"
    DEBG_RASPBERRYPI_URL="archive.raspberrypi.org/debian"

    # if [ -n "$DEBG_APT_CACHER" ]; then
    #     DEBG_DEBOOTSTRAP_URL="http://${DEBG_APT_CACHER}/${DEBG_RASPBIAN_URL}"
    # else
    #     DEBG_DEBOOTSTRAP_URL="http://${DEBG_RASPBIAN_URL}"
    # fi

    echo_notify "Generating a bootstrap from ${DEBG_DEBOOTSTRAP_URL}."

    if [ "$DEBG_SYSV" = "ON" ]; then
        DEBG_INCLUDE_PKG="locales,sysvinit-core,udev"
    else
        DEBG_INCLUDE_PKG="locales,systemd,systemd-sysv,udev"
    fi

    DEBG_INCLUDE_PKG="${DEBG_INCLUDE_PKG},ntpdate"

    trap_cleanup ()
    {
        kill $(pidof qemu-arm-static) 1> /dev/null 2>&1
        unset_chroot_operation ${DEBG_CHROOT_DIR}
        rm -rf $DEBG_CHROOT_DIR
    }

    set_trap "trap_cleanup"

    if [ -n "$DEBG_REPO_FILE" ]; then
        DEBG_REPO_URI="$(${DEBG_CURRENT_DIR}/get_aptsources_entry_data.py $DEBG_REPO_FILE 0 uri)"
        DEBG_REPO_CMP="$(${DEBG_CURRENT_DIR}/get_aptsources_entry_data.py $DEBG_REPO_FILE 0 components)"
        DEBG_DIST="$(${DEBG_CURRENT_DIR}/get_aptsources_entry_data.py $DEBG_REPO_FILE 0 suite)"
    else
        DEBG_REPO_URI="http://${DEBG_RASPBIAN_URL}"
        DEBG_REPO_CMP="main,contrib,non-free,rpi"
        DEBG_DIST="buster"
    fi

    if [ -n "$DEBG_APT_CACHER" ]; then
        DEBG_REPO_URI=$(echo $DEBG_REPO_URI | sed "s#\(http://\)\(.*\)#\1${DEBG_APT_CACHER}/\2#g")
    else
        DEBG_REPO_URI="$DEBG_REPO_URI"
    fi

    if ! debootstrap --arch="$DEBG_TARGET_ARCH" --components="$DEBG_REPO_CMP" --include="$DEBG_INCLUDE_PKG" --no-check-gpg --variant=minbase "$DEBG_DIST" "$DEBG_CHROOT_DIR" "$DEBG_REPO_URI"; then
        set +e
        trap_cleanup
        unset_trap
        echo_die 1 "debootstrap failed."
    fi

    if [ -n "$DEBG_REPO_FILE" ]; then
        cp $DEBG_REPO_FILE ${DEBG_CHROOT_DIR}/etc/apt/sources.list
    else
        cat <<EOF > ${DEBG_CHROOT_DIR}/etc/apt/sources.list
deb http://${DEBG_RASPBIAN_URL} $DEBG_DIST main contrib firmware non-free rpi
deb http://${DEBG_RASPBERRYPI_URL} $DEBG_DIST main ui untested
EOF
    fi

    if [ -n "$DEBG_APT_CACHER" ]; then
        echo "Acquire::http { Proxy \"http://${DEBG_APT_CACHER}\"; };" > ${DEBG_CHROOT_DIR}/etc/apt/apt.conf.d/99debgentmp
    fi

    setup_chroot_operation ${DEBG_CHROOT_DIR}

    _set_chroot_hostname $DEBG_CHROOT_DIR $DEBG_HOSTNAME

    cat <<EOF > ${DEBG_CHROOT_DIR}/etc/default/locale
LANG="C"
LANGUAGE="C"
EOF

    wget -q https://${DEBG_RASPBIAN_URL}.public.key -O -            | chroot "$DEBG_CHROOT_DIR" apt-key add -
    wget -q http://${DEBG_RASPBERRYPI_URL}/raspberrypi.gpg.key -O - | chroot "$DEBG_CHROOT_DIR" apt-key add -

    cat <<EOF > ${DEBG_CHROOT_DIR}/etc/apt/sources.list
deb http://${DEBG_RASPBIAN_URL} $DEBG_DIST main contrib firmware non-free rpi
deb http://${DEBG_RASPBERRYPI_URL} $DEBG_DIST main ui untested
EOF

    cat <<EOF > ${DEBG_CHROOT_DIR}/etc/udev/rules.d/10-gbr-vchiq-permissions.rules
SUBSYSTEM=="rpivid-*",GROUP="video",MODE="0660"
EOF

    if [ -z "$DEBG_NO_DEFAULT_PKG" ]; then
        chroot "$DEBG_CHROOT_DIR" /usr/bin/apt-get update
        chroot "$DEBG_CHROOT_DIR" /usr/bin/apt-get --allow-unauthenticated -y upgrade
        # Tmp caution with "raspi-copies-and-fills" and qemu-user-static version
        chroot "$DEBG_CHROOT_DIR" /usr/bin/apt-get --allow-unauthenticated -y install firmware-brcm80211 raspberrypi-bootloader raspberrypi-kernel raspi-copies-and-fills wpasupplicant $DEBG_DEFAULT_BASE_PACKAGES
    fi

    echo "root:${DEBG_ROOT_PASSWORD}" | chroot "$DEBG_CHROOT_DIR" /usr/sbin/chpasswd

    _chroot_add_pkg $DEBG_CHROOT_DIR $DEBG_ADD_PKG_LIST
    _install_deb_pkg $DEBG_CHROOT_DIR $DEBG_DEB_PKGS
    _run_in_root_system $DEBG_CHROOT_DIR $DEBG_EXE_LIST

    unset_chroot_operation "$DEBG_CHROOT_DIR"

    unset_trap

    if [ -n "$DEBG_APT_CACHER" ]; then
        rm -f ${DEBG_CHROOT_DIR}/etc/apt/apt.conf.d/99debgentmp
    fi
}

_chroot_exec ()
{
    DEBG_CHROOT_EXEC_SYNOPSIS="\
Usage: chroot-exec $DEBG_CMD_NAME [OPTIONS]
  Exec script or install package in a chroot preventing service running.

OPTIONS:
  -a, --add-package=<PKG>           Add following debian package
  -C, --apt-cacher=<APT_CACHE_ADDR> Use an temporary apt cache proxy
  -d <DEST>, --destination <DEST>   Destination file (tar gzip)
  -e, --exec=<EXE>                  Run executable
  -i, --install-deb                 Add debian file to install
  -h, --help                        Display this help
"

    OPTS=$(getopt -n chroot-exec -o 'a:d:e:hi:' -l 'add-package:,destination:,exec:,help,install-deb:' -- "$@")
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
                DEBG_ADD_PKG_LIST="$DEBG_ADD_PKG_LIST $1"
                shift
                ;;
            '-C'|'--apt-cacher')
                shift
                DEBG_APT_CACHER="$1"
                shift
                ;;
            '-d'|'--destination')
                shift
                DEBG_CHROOT_DIR="$1"
                shift
                ;;
            '-e'|'--executable')
                shift
                DEBG_EXE_LIST="$DEBG_EXE_LIST $1"
                shift
                ;;
            '-i'|'--install-deb')
                shift
                DEBG_DEB_PKGS="$DEBG_DEB_PKGS $1"
                shift
                ;;
            '-h'|'--help')
                shift
                echo "$DEBG_CHROOT_EXEC_SYNOPSIS"
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "$DEBG_CHROOT_EXEC_SYNOPSIS"
                echo_die 1 "Unknown argument $1"
                ;;
        esac
    done

    if [ $# -ne 0 ]; then
        echo "$DEBG_CHROOT_EXEC_SYNOPSIS"
        echo_die 1 "To much argument ($*)"
    fi

    if [ ! -d "$DEBG_CHROOT_DIR" ]; then
        echo_die 1 "Need a destination directory"
    fi

    if [ -n "$DEBG_EXE_LIST" -o -n "$DEBG_DEB_PKGS" -o -n "$DEBG_ADD_PKG_LIST" ]; then
        set_trap "unset_chroot_operation $DEBG_CHROOT_DIR"
        if [ -n "$DEBG_APT_CACHER" ]; then
            echo "Acquire::http { Proxy \"http://${DEBG_APT_CACHER}\"; };" > ${DEBG_CHROOT_DIR}/etc/apt/apt.conf.d/99debgentmp
        fi
        setup_chroot_operation "$DEBG_CHROOT_DIR"

        _chroot_add_pkg $DEBG_CHROOT_DIR $DEBG_ADD_PKG_LIST
        _install_deb_pkg $DEBG_CHROOT_DIR $DEBG_DEB_PKGS
        _run_in_root_system $DEBG_CHROOT_DIR $DEBG_EXE_LIST

        if [ -n "$DEBG_APT_CACHER" ]; then
            rm -f ${DEBG_CHROOT_DIR}/etc/apt/apt.conf.d/99debgentmp
        fi

        unset_chroot_operation "$DEBG_CHROOT_DIR"
        unset_trap
    fi
}

_chroot ()
{
    DEBG_CHROOT_SYNOPSIS="\
Usage: $DEBG_NAME $DEBG_CMD_NAME <CHROOT_DIR>
  Chroot preventing service running.
"

    DEBG_CHROOT_DIR="$1"
    shift

    if [ ! -d "$DEBG_CHROOT_DIR" ]; then
        echo "$DEBG_CHROOT_SYNOPSIS"
        echo_die 1 "Need a destination directory"
    fi

    set_trap "unset_chroot_operation $DEBG_CHROOT_DIR"
    setup_chroot_operation "$DEBG_CHROOT_DIR"

    chroot "$DEBG_CHROOT_DIR" "$@"

    unset_chroot_operation "$DEBG_CHROOT_DIR"
    unset_trap

}

_chroot_to_livesys_dir ()
{
    if [ ! -d "${DEBG_TMP_DIR}/chroot" -o ! -d "${DEBG_TMP_DIR}/live" ]; then
        echo_die 1 "tmp directories missing"
    fi

    echo_notify "Generating live directory in $DEBG_DST_PATH"

    echo_notify "Generating live-boot initrd and filesquahfs ..."

    if [ -n "$DEBG_APT_CACHER" ]; then
        echo "Acquire::http { Proxy \"http://${DEBG_APT_CACHER}\"; };" > ${DEBG_TMP_DIR}/chroot/etc/apt/apt.conf.d/99debgentmp
    fi

    DEBG_CHROOT_ARCH="$(chroot ${DEBG_TMP_DIR}/chroot dpkg --print-architecture)"

    if [ "$DEBG_CHROOT_ARCH" = "armhf" ]; then
        # Hack for raspbian kernel version handling
        INITRAMFS_GEN_SH=$(mktemp --suffix=_initramfs_gen.sh)
        set_trap "unset_chroot_operation ${DEBG_TMP_DIR}/chroot; rm -rf INITRAMFS_GEN_SH"
        setup_chroot_operation ${DEBG_TMP_DIR}/chroot
        cat <<EOF > $INITRAMFS_GEN_SH
#!/bin/sh -ex

for kversion in \$(ls /lib/modules); do
    mkinitramfs -o /boot/initrd-\${kversion}.img \$kversion
done
EOF
        chmod +x $INITRAMFS_GEN_SH
        _chroot_add_pkg ${DEBG_TMP_DIR}/chroot live-boot
        _run_in_root_system ${DEBG_TMP_DIR}/chroot $INITRAMFS_GEN_SH
        rm -f $INITRAMFS_GEN_SH
        unset_chroot_operation ${DEBG_TMP_DIR}/chroot
        unset_trap
    else
        set_trap "unset_chroot_operation ${DEBG_TMP_DIR}/chroot"
        setup_chroot_operation ${DEBG_TMP_DIR}/chroot
        # live-boot installation automatically run update-initramfs
        _chroot_add_pkg  ${DEBG_TMP_DIR}/chroot live-boot
        unset_chroot_operation ${DEBG_TMP_DIR}/chroot
        unset_trap
    fi

    if [ -n "$DEBG_ADD_PKG_LIST" -o -n "$DEBG_DEB_PKGS" -o -n "$DEBG_EXE_LIST" ]; then
        setup_chroot_operation ${DEBG_TMP_DIR}/chroot
        _chroot_add_pkg ${DEBG_TMP_DIR}/chroot $DEBG_ADD_PKG_LIST
        _install_deb_pkg ${DEBG_TMP_DIR}/chroot $DEBG_DEB_PKGS
        _run_in_root_system ${DEBG_TMP_DIR}/chroot $DEBG_EXE_LIST
        unset_chroot_operation ${DEBG_TMP_DIR}/chroot
    fi

    if [ -n "$DEBG_APT_CACHER" ]; then
        rm -f ${DEBG_TMP_DIR}/chroot/etc/apt/apt.conf.d/99debgentmp
    fi

    if [ -n "$DEBG_PERSISTENCE_PATHS" ]; then
        mkdir ${DEBG_TMP_DIR}/live/persistence
        for ppath in $DEBG_PERSISTENCE_PATHS; do
            if [ ! -d ${DEBG_TMP_DIR}/chroot${ppath} ]; then
                mkdir -p ${DEBG_TMP_DIR}/chroot${ppath}
            fi
            mv ${DEBG_TMP_DIR}/chroot${ppath} ${DEBG_TMP_DIR}/live/persistence
            echo "$ppath source=persistence/$(basename $ppath)" >> ${DEBG_TMP_DIR}/live/persistence.conf
        done
    fi

    mv ${DEBG_TMP_DIR}/chroot/boot/* ${DEBG_TMP_DIR}/live

    mkdir ${DEBG_TMP_DIR}/live/live
    mksquashfs ${DEBG_TMP_DIR}/chroot ${DEBG_TMP_DIR}/live/live/filesystem.squashfs
    rm -rf ${DEBG_TMP_DIR}/chroot
}

_handle_dir_to_livesys_args ()
{
    DEBG_LIVESYS_SYNOPSIS="\
Usage: $DEBG_NAME $DEBG_CMD_NAME [OPTIONS]
  Convert a chroot to a live system an flash it to a block device or a file.

OPTIONS:
  -a <PKG>, --add-package=<PKG>     Add following debian package to the image
  -C, --apt-cacher=<APT_CACHE_ADDR> Use an temporary apt cache proxy
  -d <DST>, --destination <DST>     Destination path
  -e <EXE>, --exec=<EXE>            Run executable into the new system
  -h, --help                        Display this help
  -i, --install-deb                      Add debian file to install
  -s <SRC>, --source=<SRC>          Source chroot directory
  -p, --add-persistence=PATH        Add persistency on specified path
"

    OPTS=$(getopt -n "$DEBG_CMD_NAME" -o 'a:C:d:e:hi:p:s:' -l 'add-package:,apt-cacher:,destination:,exec:,help,install-deb:,source:,add-persistence:' -- "$@")
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
                DEBG_ADD_PKG_LIST="$DEBG_ADD_PKG_LIST $1"
                shift
                ;;
            '-C'|'--apt-cacher')
                shift
                DEBG_APT_CACHER="$1"
                shift
                ;;
            '-d'|'--destination')
                shift
                DEBG_DST_PATH="$1"
                shift
                ;;
            '-e'|'--executable')
                shift
                DEBG_EXE_LIST="$DEBG_EXE_LIST $1"
                shift
                ;;
            '-h'|'--help')
                echo "$DEBG_LIVESYS_SYNOPSIS"
                exit 0
                ;;
            '-i'|'--install-deb')
                shift
                DEBG_DEB_PKGS="$DEBG_DEB_PKGS $1"
                shift
                ;;
            '-p'|'--add-persistence')
                shift
                DEBG_PERSISTENCE_PATHS="$DEBG_PERSISTENCE_PATHS $1"
                shift
                ;;
            '-s'|'--source')
                shift
                DEBG_SRC_PATH="$1"
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "$DEBG_LIVESYS_SYNOPSIS"
                echo_die 1 "Wrong argument $1"
                ;;
        esac
    done

    if [ -z "$DEBG_DST_PATH" ]; then
        echo "$DEBG_LIVESYS_SYNOPSIS"
        echo_die 1 "Destination is mandatory"
    fi

    if [ -n "$DEBG_SRC_PATH" ]; then
        if [ ! -d "$DEBG_SRC_PATH" ]; then
            echo "$DEBG_LIVESYS_SYNOPSIS"
            echo_die 1 "$DEBG_SRC_PATH chroot source is not a directory"
        fi
    fi
}

_chroot_to_live_squashfs ()
{
    _handle_dir_to_livesys_args "$@"

    if [ -e "$DEBG_DST_PATH" ]; then
        echo_die 1 "Destination already exist"
    fi

    DEBG_TMP_DIR="$(mktemp -d --suffix=_debg_tmp_dir)"
    DEBG_EXCLUSION_FILE="$(mktemp --suffix=_debg_exclusion)"
    set_trap "unset_chroot_operation $DEBG_TMP_DIR; rm -rf $DEBG_EXCLUSION_FILE $DEBG_TMP_DIR"

    echo_notify "Copying chroot directory ..."
    rsync -ad ${DEBG_SRC_PATH}/* ${DEBG_TMP_DIR}/
    echo_notify "Copy done."

    if [ -n "$DEBG_APT_CACHER" ]; then
        echo "Acquire::http { Proxy \"http://${DEBG_APT_CACHER}\"; };" > ${DEBG_TMP_DIR}/etc/apt/apt.conf.d/99debgentmp
    fi

    setup_chroot_operation $DEBG_TMP_DIR
    _chroot_add_pkg $DEBG_TMP_DIR live-boot
    _chroot_add_pkg $DEBG_TMP_DIR $DEBG_ADD_PKG_LIST
    _install_deb_pkg $DEBG_TMP_DIR $DEBG_DEB_PKGS
    _run_in_root_system $DEBG_TMP_DIR $DEBG_EXE_LIST
    unset_chroot_operation $DEBG_TMP_DIR

    if [ -n "$DEBG_APT_CACHER" ]; then
        rm -f ${DEBG_TMP_DIR}/etc/apt/apt.conf.d/99debgentmp
    fi

    for pers_path in $DEBG_PERSISTENCE_PATHS; do
        rm -rf ${DEBG_TMP_DIR}${pers_path}
    done

    rm -rf ${DEBG_TMP_DIR}/boot/*

    mksquashfs $DEBG_TMP_DIR $DEBG_DST_PATH

    unset_trap
    rm -rf $DEBG_EXCLUSION_FILE $DEBG_TMP_DIR
}
