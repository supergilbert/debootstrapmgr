#!/bin/sh

. ${DMGR_CURRENT_DIR}/functions.sh

DEFAULT_LIVE_JSON="\
{
    \"disks\": [
        {
            \"table\": \"msdos\",
            \"parts\": [
                {
                    \"type\": \"fat32\",
                    \"volname\": \"persistence\"}
            ]
        }
    ],
    \"systems\": [
        {
            \"type\": \"debian-live-boot\",
            \"disk\": 0,
            \"partidx\": 0
        }
    ]
}
"

DEFAULT_FSTAB_JSON="\
{
    \"disks\": [
        {
            \"table\": \"XXXTABLEXXX\",
            \"parts\": [
                {
                    \"type\": \"fat32\",
                    \"volname\": \"boot\",
                    \"partname\": \"boot\",
                    \"size\": \"500M\"
                },
                {
                    \"type\": \"linux-swap\",
                    \"volname\": \"swap\",
                    \"partname\": \"swap\",
                    \"size\": \"XXXSWAPSIZEXXX\"
                },
                {
                    \"type\": \"ext4\",
                    \"volname\": \"sys\",
                    \"partname\": \"sys\"
                }
            ]
        }
    ],
    \"systems\": [
        {
            \"type\": \"fstab\",
            \"disk\": 0,
            \"partidx\": 2,
            \"parts\": [
                {
                    \"disk\": 0,
                    \"partidx\": 1
                },
                {
                    \"disk\": 0,
                    \"partidx\": 0,
                    \"mount\": \"/boot\"
                }
            ]
        }
    ]
}
"

DEFAULT_FSTAB_RPI_JSON="\
{
    \"disks\": [
        {
            \"table\": \"msdos\",
            \"parts\": [
                {
                    \"type\": \"fat32\",
                    \"volname\": \"boot\",
                    \"partname\": \"boot\",
                    \"size\": \"500M\"
                },
                {
                    \"type\": \"ext4\",
                    \"volname\": \"sys\",
                    \"partname\": \"sys\"
                }
            ]
        }
    ],
    \"systems\": [
        {
            \"type\": \"fstab\",
            \"disk\": 0,
            \"partidx\": 1,
            \"parts\": [
                {
                    \"disk\": 0,
                    \"partidx\": 0,
                    \"mount\": \"/boot\"
                }
            ]
        }
    ]
}
"

# PC Part

# DMGR_SIZE_1G=1048576

_handle_flash_args ()
{
    DMGR_PC_FLASHIMG_SYNOPSIS="\
Usage: $DMGR_NAME $DMGR_CMD_NAME [OPTIONS]
  Flash a chroot to a block device or a file.

OPTIONS:
  -a <PKG>, --add-package=<PKG> Add following debian package to the image
  -d <DST>, --destination=<DST> Destination path
  -e <EXE>, --exec=<EXE>        Run executable into the new system
  -E, --efi                     Install grub-efi-amd64 instead of grub-pc
  -i, --install-deb             Add debian file to install
  -j <JSON>, --json <JSON>      Specify a json filesystem architecture
  -g, --gpt                     Setup an \"GPT\" partition table
                                instead of \"MSDOS\"
  -s <SRC>, --source=<SRC>      Chroot directory
  -S <SIZE>, --size=<SIZE>      Set image giga-octet size
  -w <SIZE>, --swap=<SIZE>      Swap size in Go (default 2Go)
  -h, --help                    Display this help
"

    OPTS=$(getopt -n "$DMGR_CMD_NAME" -o 'a:d:e:Egj:hi:s:S:w:' -l 'add-package:,destination:,exec:,efi,gpt,json:,help,image-size:,install-deb:,source:,swap:' -- "$@")
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
            '-E'|'--efi')
                shift
                DMGR_GRUBEFI="on"
                echo_notify "Setup system boot in UEFI mode"
                ;;
            '-i'|'--install-deb')
                shift
                DMGR_DEB_PKGS="$DMGR_DEB_PKGS $1"
                shift
                ;;
            '-j'|'--json')
                shift
                DMGR_JSON_ARG="$1"
                shift
                ;;
            '-s'|'--source')
                shift
                DMGR_SRC_DIR="$1"
                shift
                ;;
            '-S'|'--size')
                shift
                DMGR_IMG_SIZE="$1"
                shift
                ;;
            '-g'|'--gpt')
                shift
                DMGR_GPTTABLE="on"
                echo_notify "Setup an MSDOS partition table"
                ;;
            '-w'|'--swap')
                shift
                DMGR_SWAP_SIZE="$1"
                shift
                ;;
            '-h'|'--help')
                echo "$DMGR_PC_FLASHIMG_SYNOPSIS"
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "$DMGR_PC_FLASHIMG_SYNOPSIS"
                echo_die 1 "Wrong argument $1"
                ;;
        esac
    done

    if [ -z "$DMGR_DST_PATH" ]; then
        echo "$DMGR_PC_FLASHIMG_SYNOPSIS"
        echo_die 1 "Destination is mandatory"
    fi

    if [ ! -d "$DMGR_SRC_DIR" ]; then
        echo "$DMGR_PC_FLASHIMG_SYNOPSIS"
        echo_die 1 "$DMGR_SRC_DIR chroot source directory does not exist"
    fi

    if [ -n "$DMGR_EXE_LIST" ]; then
        check_exe_list $DMGR_EXE_LIST
    fi

    if [ -n "$DMGR_DEB_PKGS" ]; then
        check_file_list $DMGR_DEB_PKGS
    fi

    if [ -z "$DMGR_SWAP_SIZE" ]; then
        # Default 2Go
        DMGR_SWAP_SIZE="2G"
    fi
    if [ "$DMGR_GRUBEFI" != "on" -a "$DMGR_GPTTABLE" = "on" ]; then
        echo_die 1 "Cannot install MBR on gpt table"
    fi

    diskhdr_cmd="${DMGR_CURRENT_DIR}/diskhdr.py"

    if [ -n "$DMGR_JSON_ARG" ]; then
        DMGR_JSON="$DMGR_JSON_ARG"
    fi

    if [ -e "$DMGR_DST_PATH" ]; then
        DMGR_DST_PATH="$(realpath $DMGR_DST_PATH)"
        if [ ! -b "$DMGR_DST_PATH" ]; then
            echo_die 1 "$DMGR_DST_PATH image already exist or is not a block device"
        else
            if [ -n "$DMGR_IMG_SIZE" ]; then
                echo_die 1 "Can not set size on block device"
            fi
        fi
    else
        DMGR_IMAGE_TYPE="ON"
    fi
}

_echo_dir_ko_size ()
{
    du -s --apparent-size $1 2>/dev/null | sed 's/\([[:digit:]]\+\)[[:space:]]\+.*/\1/'
}

_echo_dir_mo_size ()
{
    echo "$((($(_echo_dir_ko_size $1) / 1024) + 1))"
}

_get_sys_min_size ()
{
    _CHROOT_DIR=$1
    _SIZE="$(_echo_dir_mo_size $_CHROOT_DIR)"
    for mount_path in $($diskhdr_cmd $DMGR_JSON mounts 0); do
        _SIZE=$(($_SIZE - $(_echo_dir_mo_size ${_CHROOT_DIR}${mount_path})))
    done
    echo $_SIZE
}

_handle_flash_dest_copy_n_set_trap ()
{
    # TODO factorise with rpi
    unset_trap
    if [ "$DMGR_IMAGE_TYPE" = "ON" ]; then
        echo_notify "Generating image file in $DMGR_DST_PATH"
        DMGR_MIN_SIZE="$(($(_get_sys_min_size ${DMGR_TMP_DIR}/chroot) + $($diskhdr_cmd $DMGR_JSON minsize 0)))"
        DMGR_MIN_SIZE="$(($DMGR_MIN_SIZE * 110 / 100))"
        if [ -z "$DMGR_IMG_SIZE" ]; then
            truncate -s ${DMGR_MIN_SIZE}M $DMGR_DST_PATH
        else
            if [ "$(($DMGR_IMG_SIZE * 1024))" -lt "$DMGR_MIN_SIZE" ];then
                echo_die 1 "Size ${DMGR_IMG_SIZE}G is less than ${DMGR_MINK_SIZE}K"
            fi
            truncate -s ${DMGR_IMG_SIZE}G $DMGR_DST_PATH
        fi
        if [ -n "$DMGR_JSON_ARG" ]; then
            set_trap "unset_chroot_operation ${DMGR_TMP_DIR}/mnt; $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH ${DMGR_TMP_DIR}/mnt; rm -rf $DMGR_DST_PATH $DMGR_TMP_DIR"
        else
            set_trap "unset_chroot_operation ${DMGR_TMP_DIR}/mnt; $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH ${DMGR_TMP_DIR}/mnt; rm -rf $DMGR_DST_PATH $DMGR_TMP_DIR $DMGR_JSON"
        fi
    else
        if [ -n "$DMGR_JSON_ARG" ]; then
            set_trap "unset_chroot_operation ${DMGR_TMP_DIR}/mnt; $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH ${DMGR_TMP_DIR}/mnt; rm -rf $DMGR_TMP_DIR"
        else
            set_trap "unset_chroot_operation ${DMGR_TMP_DIR}/mnt; $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH ${DMGR_TMP_DIR}/mnt; rm -rf $DMGR_TMP_DIR $DMGR_JSON"
        fi
    fi

    $diskhdr_cmd $DMGR_JSON format $DMGR_DST_PATH
    DMGR_FSTAB_STR="$($diskhdr_cmd $DMGR_JSON fstab 0 $DMGR_DST_PATH)"
    $diskhdr_cmd $DMGR_JSON mount 0 $DMGR_DST_PATH ${DMGR_TMP_DIR}/mnt

    echo_notify "Copying files ..."
    rsync -ad ${DMGR_TMP_DIR}/chroot/* ${DMGR_TMP_DIR}/mnt/
    echo_notify "Files copy done"
    echo "$DMGR_FSTAB_STR" > ${DMGR_TMP_DIR}/mnt/etc/fstab

    rm -rf ${DMGR_TMP_DIR}/chroot
}

_pc_chroot_flash ()
{
    _handle_flash_args "$@"

    DMGR_TMP_DIR="$(mktemp -d --suffix=_dbr_img_tmp_dir)"
    mkdir ${DMGR_TMP_DIR}/chroot ${DMGR_TMP_DIR}/mnt

    set_trap "unset_chroot_operation ${DMGR_TMP_DIR}/chroot; rm -rf $DMGR_TMP_DIR"

    # TODO if no src generate default chroot
    echo_notify "Copying files ..."
    rsync -ad ${DMGR_SRC_DIR}/* ${DMGR_TMP_DIR}/chroot
    echo_notify "Files copy done"

    # chroot installations
    setup_chroot_operation ${DMGR_TMP_DIR}/chroot

    if [ -n "$DMGR_GRUBEFI" ]; then
        chroot ${DMGR_TMP_DIR}/chroot apt update
        chroot ${DMGR_TMP_DIR}/chroot apt -y install grub-efi-amd64 grub-efi-amd64-signed
    else
        chroot ${DMGR_TMP_DIR}/chroot apt update
        chroot ${DMGR_TMP_DIR}/chroot apt -y install grub-pc
    fi

    _chroot_add_pkg ${DMGR_TMP_DIR}/chroot $DMGR_ADD_PKG_LIST
    _install_deb_pkg ${DMGR_TMP_DIR}/chroot $DMGR_DEB_PKGS
    _run_in_root_system ${DMGR_TMP_DIR}/chroot $DMGR_EXE_LIST

    unset_chroot_operation ${DMGR_TMP_DIR}/chroot

    unset_trap
    set_trap "rm -rf $DMGR_TMP_DIR"

    if [ -z "$DMGR_JSON"]; then
        if [ -n "$DMGR_GPTTABLE" ]; then
            PART_TABLE="gpt"
        else
            PART_TABLE="msdos"
        fi
        DMGR_JSON="${DMGR_TMP_DIR}/diskhdr.json"
        echo "$DEFAULT_FSTAB_JSON" | sed "s/XXXTABLEXXX/${PART_TABLE}/g;s/XXXSWAPSIZEXXX/${DMGR_SWAP_SIZE}/g" > $DMGR_JSON
    fi

    _handle_flash_dest_copy_n_set_trap

    # Grub installation

    if [ -n "$DMGR_IMAGE_TYPE" ]; then
        DMGR_BLKDEV=$(losetup --raw | grep $DMGR_DST_PATH | cut -f 1 -d' ')
    else
        DMGR_BLKDEV=$DMGR_DST_PATH
    fi

    setup_chroot_operation ${DMGR_TMP_DIR}/mnt

    _dmgr_install_tmp_grub_cfg ()
    {
        GRUB_CFG_PATH=${DMGR_TMP_DIR}/mnt/etc/default/grub.d/dmgr.cfg
        cat <<EOF > $GRUB_CFG_PATH
GRUB_DISABLE_OS_PROBER="true"
EOF
        sed -i 's/#GRUB_DISABLE_RECOVERY="true"/GRUB_DISABLE_RECOVERY="true"/' ${DMGR_TMP_DIR}/mnt/etc/default/grub
        cat <<EOF > ${DMGR_TMP_DIR}/mnt/boot/grub/device.map
(hd0) $DMGR_BLKDEV
EOF
    }

    if [ -n "$DMGR_GRUBEFI" ]; then
        _dmgr_install_tmp_grub_cfg

        echo_notify "Installing grub"
        chroot ${DMGR_TMP_DIR}/mnt grub-install --removable --target=x86_64-efi --boot-directory=/boot --efi-directory=/boot --force || true
        chroot ${DMGR_TMP_DIR}/mnt update-grub || true
        echo_notify "grub installed"
    else
        _dmgr_install_tmp_grub_cfg

        echo_notify "Installing grub"
        chroot ${DMGR_TMP_DIR}/mnt grub-install --force --target=i386-pc $DMGR_BLKDEV || true
        chroot ${DMGR_TMP_DIR}/mnt grub-mkconfig -o /boot/grub/grub.cfg || true
        echo_notify "grub installed"
    fi

    rm ${DMGR_TMP_DIR}/mnt/boot/grub/device.map $GRUB_CFG_PATH

    unset_chroot_operation ${DMGR_TMP_DIR}/mnt

    # End of grub installation

    $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH ${DMGR_TMP_DIR}/mnt

    if [ -z "$DMGR_JSON_ARG" ]; then
        rm -f $DMGR_JSON
    fi

    rm -rf $DMGR_TMP_DIR

    unset_trap
}

_handle_flashlive_block_or_file ()
{
    DMGR_JSON="$(mktemp --suffix=_json)"
    echo $DEFAULT_LIVE_JSON > $DMGR_JSON

    if [ -e "$DMGR_DST_PATH" ]; then
        DMGR_DST_PATH="$(realpath $DMGR_DST_PATH)"
        if [ ! -b "$DMGR_DST_PATH" ]; then
            echo_die 1 "$DMGR_DST_PATH already exist"
        fi
        echo_notify "Flashing block device"
        set_trap "$diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH ${DMGR_TMP_DIR}/mnt; rm -rf $DMGR_TMP_DIR $DMGR_JSON"
    else
        echo_notify "Flashing image file"
        DMGR_LIVEDIR_SIZE="$(_echo_dir_ko_size ${DMGR_TMP_DIR}/live)"
        # Add 100000K(~100M) for grub
        DMGR_LIVEIMG_SIZE="$((($DMGR_LIVEDIR_SIZE * 110 / 100) + 100000))"
        truncate -s ${DMGR_LIVEIMG_SIZE}K $DMGR_DST_PATH
        set_trap "$diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH ${DMGR_TMP_DIR}/mnt; rm -rf $DMGR_TMP_DIR $DMGR_JSON $DMGR_DST_PATH"
    fi
}

_pc_chroot_flashlive ()
{
    _handle_dir_to_livesys_args "$@"

    echo_notify "Generating live system"
    DMGR_TMP_DIR="$(mktemp -d --suffix=_dmgr_livesys_dir)"
    mkdir ${DMGR_TMP_DIR}/live ${DMGR_TMP_DIR}/mnt

    # nb: _chroot_to_livesys_dir use set_trap
    _chroot_to_livesys_dir $DMGR_SRC_PATH ${DMGR_TMP_DIR}/live

    diskhdr_cmd="${DMGR_CURRENT_DIR}/diskhdr.py"

    _handle_flashlive_block_or_file

    $diskhdr_cmd $DMGR_JSON format $DMGR_DST_PATH
    $diskhdr_cmd $DMGR_JSON mount 0 $DMGR_DST_PATH ${DMGR_TMP_DIR}/mnt

    rsync --modify-window=1 --update --recursive ${DMGR_TMP_DIR}/live/* ${DMGR_TMP_DIR}/mnt

    # Setup Boot
    mv ${DMGR_TMP_DIR}/mnt/vmlinuz* ${DMGR_TMP_DIR}/mnt/vmlinuz
    mv ${DMGR_TMP_DIR}/mnt/initrd.img* ${DMGR_TMP_DIR}/mnt/initrd.img

    grub-install --target=i386-pc --boot-directory=${DMGR_TMP_DIR}/mnt $DMGR_DST_PATH
    cat <<EOF > ${DMGR_TMP_DIR}/mnt/grub/grub.cfg
insmod ext2
set root='hd0,msdos1'
linux /vmlinuz boot=live components persistence
initrd /initrd.img
boot
EOF
    # End of boot setup

    $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH ${DMGR_TMP_DIR}/mnt

    rm -rf $DMGR_TMP_DIR $DMGR_JSON
    unset_trap
}

# RPI Part

_rpi_chroot_flash ()
{
    _handle_flash_args "$@"

    DMGR_TMP_DIR="$(mktemp -d --suffix=_dbr_img_tmp_dir)"
    mkdir ${DMGR_TMP_DIR}/chroot ${DMGR_TMP_DIR}/mnt

    set_trap "unset_chroot_operation ${DMGR_TMP_DIR}/chroot; rm -rf $DMGR_TMP_DIR"

    # TODO if no src generate default chroot
    echo_notify "Copying files ..."
    rsync -ad ${DMGR_SRC_DIR}/* ${DMGR_TMP_DIR}/chroot
    echo_notify "Files copy done"

    if [ -n "$DMGR_ADD_PKG_LIST" -o -n "$DMGR_DEB_PKGS" -o -n "$DMGR_EXE_LIST" ]; then
        setup_chroot_operation ${DMGR_TMP_DIR}/chroot
        _chroot_add_pkg ${DMGR_TMP_DIR}/chroot $DMGR_ADD_PKG_LIST
        _install_deb_pkg ${DMGR_TMP_DIR}/chroot $DMGR_DEB_PKGS
        _run_in_root_system ${DMGR_TMP_DIR}/chroot $DMGR_EXE_LIST
        unset_chroot_operation ${DMGR_TMP_DIR}/chroot
    fi

    unset_trap

    if [ -z "$DMGR_JSON"]; then
        DMGR_JSON="${DMGR_TMP_DIR}/diskhdr.json"
        echo "$DEFAULT_FSTAB_RPI_JSON" > $DMGR_JSON
    fi

    _handle_flash_dest_copy_n_set_trap

    $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH ${DMGR_TMP_DIR}/mnt

    if [ -z "$DMGR_JSON_ARG" ]; then
        rm -f $DMGR_JSON
    fi

    rm -rf $DMGR_TMP_DIR

    unset_trap
}

_rpi_chroot_flashlive ()
{
    _handle_dir_to_livesys_args "$@"

    DMGR_TYPE="RPI"

    echo_notify "Generating live system"
    DMGR_TMP_DIR="$(mktemp -d --suffix=_dmgr_livesys_dir)"
    mkdir ${DMGR_TMP_DIR}/live ${DMGR_TMP_DIR}/mnt

    # nb: _chroot_to_livesys_dir use set_trap
    _chroot_to_livesys_dir $DMGR_SRC_PATH ${DMGR_TMP_DIR}/live

    diskhdr_cmd="${DMGR_CURRENT_DIR}/diskhdr.py"

    _handle_flashlive_block_or_file

    $diskhdr_cmd $DMGR_JSON format $DMGR_DST_PATH
    $diskhdr_cmd $DMGR_JSON mount 0 $DMGR_DST_PATH ${DMGR_TMP_DIR}/mnt

    rsync --modify-window=1 --update --recursive ${DMGR_TMP_DIR}/live/* ${DMGR_TMP_DIR}/mnt

    # Setup Boot
    mv ${DMGR_TMP_DIR}/mnt/initrd*v7+.img ${DMGR_TMP_DIR}/mnt/initrd7.img
    mv ${DMGR_TMP_DIR}/mnt/initrd*v7l+.img ${DMGR_TMP_DIR}/mnt/initrd7l.img
    mv ${DMGR_TMP_DIR}/mnt/initrd*v8+.img ${DMGR_TMP_DIR}/mnt/initrd8.img
    mv ${DMGR_TMP_DIR}/mnt/initrd*+.img ${DMGR_TMP_DIR}/mnt/initrd.img
    echo_notify "live-boot and initrd generation done"

    echo_notify "Setting up boot load"
    cat <<EOF > ${DMGR_TMP_DIR}/mnt/config.txt
kernel kernel7l.img
initramfs initrd7l.img followkernel
gpu_mem=320
dtoverlay=vc4-fkms-v3d
dtparam=audio=on
disable_overscan=1
EOF
    cat <<EOF > ${DMGR_TMP_DIR}/mnt/cmdline.txt
live-media=/dev/mmcblk0p1 rootwait cma=512M boot=live components persistence
EOF
    # End of boot setup

    $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH ${DMGR_TMP_DIR}/mnt

    rm -rf $DMGR_TMP_DIR $DMGR_JSON
    unset_trap
}
