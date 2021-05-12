. ${DEBG_CURRENT_DIR}/functions.sh

DEFAULT_LIVE_JSON="\
{
    \"disks\": [
        {
            \"table\": \"msdos\",
            \"parts\": [
                {
                    \"type\": \"fat32\",
                    \"volname\": \"persistence\"
                }
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

# DEBG_SIZE_1G=1048576

_handle_flash_args ()
{
    DEBG_PC_FLASHIMG_SYNOPSIS="\
Usage: $DEBG_NAME $DEBG_CMD_NAME [OPTIONS]
  Flash a chroot to a block device or a file.

OPTIONS:
  -a <PKG>, --add-package=<PKG> Add following debian package to the image
  -d <DST>, --destination=<DST> Destination path
  -e <EXE>, --exec=<EXE>        Run executable into the new system
  -E, --efi                     Install grub-efi instead of grub-pc
  -i, --install-deb             Add debian file to install
  -j <JSON>, --json <JSON>      Specify a json filesystem architecture
  -g, --gpt                     Setup an \"GPT\" partition table
                                instead of \"MSDOS\"
  -s <SRC>, --source=<SRC>      Chroot directory
  -S <SIZE>, --size=<SIZE>      Set image giga-octet size
  -w <SIZE>, --swap=<SIZE>      Swap size in Go (default 2Go)
  -h, --help                    Display this help
"

    OPTS=$(getopt -n "$DEBG_CMD_NAME" -o 'a:d:e:Egj:hi:s:S:w:' -l 'add-package:,destination:,exec:,efi,gpt,json:,help,image-size:,install-deb:,source:,swap:' -- "$@")
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
            '-E'|'--efi')
                shift
                DEBG_GRUBEFI="on"
                echo_notify "Setup system boot in UEFI mode"
                ;;
            '-i'|'--install-deb')
                shift
                DEBG_DEB_PKGS="$DEBG_DEB_PKGS $1"
                shift
                ;;
            '-j'|'--json')
                shift
                DEBG_JSON_ARG="$1"
                shift
                ;;
            '-s'|'--source')
                shift
                DEBG_SRC_PATH="$1"
                shift
                ;;
            '-S'|'--size')
                shift
                DEBG_IMG_SIZE="$1"
                shift
                ;;
            '-g'|'--gpt')
                shift
                DEBG_GPTTABLE="on"
                echo_notify "Setup an MSDOS partition table"
                ;;
            '-w'|'--swap')
                shift
                DEBG_SWAP_SIZE="$1"
                shift
                ;;
            '-h'|'--help')
                echo "$DEBG_PC_FLASHIMG_SYNOPSIS"
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "$DEBG_PC_FLASHIMG_SYNOPSIS"
                echo_die 1 "Wrong argument $1"
                ;;
        esac
    done

    if [ -z "$DEBG_DST_PATH" ]; then
        echo "$DEBG_PC_FLASHIMG_SYNOPSIS"
        echo_die 1 "Destination is mandatory"
    fi

    if [ -n "$DEBG_SRC_PATH" ]; then
        if [ ! -d "$DEBG_SRC_PATH" -a ! -f "$DEBG_SRC_PATH" ]; then
            echo "$DEBG_PC_FLASHIMG_SYNOPSIS"
            echo_die 1 "$DEBG_SRC_PATH chroot source is not a directory or a regular flie"
        fi
    fi

    if [ -n "$DEBG_EXE_LIST" ]; then
        check_exe_list $DEBG_EXE_LIST
    fi

    if [ -n "$DEBG_DEB_PKGS" ]; then
        check_file_list $DEBG_DEB_PKGS
    fi

    if [ -z "$DEBG_SWAP_SIZE" ]; then
        # Default 2Go
        DEBG_SWAP_SIZE="2G"
    fi
    if [ "$DEBG_GRUBEFI" != "on" -a "$DEBG_GPTTABLE" = "on" ]; then
        echo_die 1 "Cannot install MBR on gpt table"
    fi

    diskhdr_cmd="${DEBG_CURRENT_DIR}/diskhdr.py"

    if [ -n "$DEBG_JSON_ARG" ]; then
        DEBG_JSON="$DEBG_JSON_ARG"
    fi

    if [ -e "$DEBG_DST_PATH" ]; then
        DEBG_DST_PATH="$(realpath $DEBG_DST_PATH)"
        if [ ! -b "$DEBG_DST_PATH" ]; then
            echo_die 1 "$DEBG_DST_PATH image already exist or is not a block device"
        else
            if [ -n "$DEBG_IMG_SIZE" ]; then
                echo_die 1 "Can not set size on block device"
            fi
        fi
    else
        DEBG_IMAGE_TYPE="ON"
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
    for mount_path in $($diskhdr_cmd $DEBG_JSON mounts 0); do
        _SIZE=$(($_SIZE - $(_echo_dir_mo_size ${_CHROOT_DIR}${mount_path})))
    done
    echo $_SIZE
}

_dest_format_mount_copy_n_set_trap ()
{
    # TODO factorise with rpi
    unset_trap
    if [ "$DEBG_IMAGE_TYPE" = "ON" ]; then
        echo_notify "Generating image file in $DEBG_DST_PATH"
        DEBG_MIN_SIZE="$(($(_get_sys_min_size ${DEBG_TMP_DIR}/chroot) + $($diskhdr_cmd $DEBG_JSON minsize 0)))"
        DEBG_MIN_SIZE="$(($DEBG_MIN_SIZE * 110 / 100))"
        if [ -z "$DEBG_IMG_SIZE" ]; then
            truncate -s ${DEBG_MIN_SIZE}M $DEBG_DST_PATH
        else
            if [ "$(($DEBG_IMG_SIZE * 1024))" -lt "$DEBG_MIN_SIZE" ];then
                echo_die 1 "Size ${DEBG_IMG_SIZE}G is less than ${DEBG_MINK_SIZE}K"
            fi
            truncate -s ${DEBG_IMG_SIZE}G $DEBG_DST_PATH
        fi
        if [ -n "$DEBG_JSON_ARG" ]; then
            set_trap "unset_chroot_operation ${DEBG_TMP_DIR}/mnt; $diskhdr_cmd $DEBG_JSON umount 0 $DEBG_DST_PATH ${DEBG_TMP_DIR}/mnt; rm -rf $DEBG_DST_PATH $DEBG_TMP_DIR"
        else
            set_trap "unset_chroot_operation ${DEBG_TMP_DIR}/mnt; $diskhdr_cmd $DEBG_JSON umount 0 $DEBG_DST_PATH ${DEBG_TMP_DIR}/mnt; rm -rf $DEBG_DST_PATH $DEBG_TMP_DIR $DEBG_JSON"
        fi
    else
        if [ -n "$DEBG_JSON_ARG" ]; then
            set_trap "unset_chroot_operation ${DEBG_TMP_DIR}/mnt; $diskhdr_cmd $DEBG_JSON umount 0 $DEBG_DST_PATH ${DEBG_TMP_DIR}/mnt; rm -rf $DEBG_TMP_DIR"
        else
            set_trap "unset_chroot_operation ${DEBG_TMP_DIR}/mnt; $diskhdr_cmd $DEBG_JSON umount 0 $DEBG_DST_PATH ${DEBG_TMP_DIR}/mnt; rm -rf $DEBG_TMP_DIR $DEBG_JSON"
        fi
    fi

    $diskhdr_cmd $DEBG_JSON format $DEBG_DST_PATH
    DEBG_FSTAB_STR="$($diskhdr_cmd $DEBG_JSON fstab 0 $DEBG_DST_PATH)"
    DEBG_BLKDEV="$($diskhdr_cmd $DEBG_JSON mount 0 $DEBG_DST_PATH ${DEBG_TMP_DIR}/mnt)"

    echo_notify "Copying files ..."
    rsync -ad ${DEBG_TMP_DIR}/chroot/* ${DEBG_TMP_DIR}/mnt/
    echo_notify "Files copy done"
    echo "$DEBG_FSTAB_STR" > ${DEBG_TMP_DIR}/mnt/etc/fstab

    rm -rf ${DEBG_TMP_DIR}/chroot
}

_handle_flash_src_path_to_tmp_dir ()
{
    echo_notify "Copying files ..."
    mkdir ${DEBG_TMP_DIR}/chroot
    if [ -d "$DEBG_SRC_PATH" ]; then
        rsync -ad ${DEBG_SRC_PATH}/* ${DEBG_TMP_DIR}/chroot/
    else
        tar -xf ${DEBG_SRC_PATH} -C ${DEBG_TMP_DIR}/chroot/
    fi
    echo_notify "Files copy done"
}

_flash_pc ()
{
    _handle_flash_args "$@"

    DEBG_TMP_DIR="$(mktemp -d --suffix=_dbr_img_tmp_dir)"

    set_trap "unset_chroot_operation ${DEBG_TMP_DIR}/chroot; rm -rf $DEBG_TMP_DIR"

    mkdir ${DEBG_TMP_DIR}/mnt
    if [ -n "$DEBG_SRC_PATH" ]; then
        _handle_flash_src_path_to_tmp_dir
    else
        mkdir ${DEBG_TMP_DIR}/mnt
        echo_notify "No source chroot provided generating a default one"
        ${DEBG_CURRENT_DIR}/debgen.sh pc-chroot -d ${DEBG_TMP_DIR}/chroot
    fi

    # chroot installations
    setup_chroot_operation ${DEBG_TMP_DIR}/chroot

    if [ -n "$DEBG_GRUBEFI" ]; then
        DEBG_CHROOT_ARCH="$(chroot ${DEBG_TMP_DIR}/chroot dpkg --print-architecture)"
        if [ "$DEBG_CHROOT_ARCH" = "amd64" ]; then
            DEBG_GRUB_EFI_PKG="grub-efi-amd64 grub-efi-amd64-signed"
        else
            DEBG_GRUB_EFI_PKG="grub-efi-ia32 grub-efi-ia32-signed"
        fi

        chroot ${DEBG_TMP_DIR}/chroot apt update
        chroot ${DEBG_TMP_DIR}/chroot apt -y install $DEBG_GRUB_EFI_PKG
    else
        chroot ${DEBG_TMP_DIR}/chroot apt update
        chroot ${DEBG_TMP_DIR}/chroot apt -y install grub-pc
    fi

    _chroot_add_pkg ${DEBG_TMP_DIR}/chroot $DEBG_ADD_PKG_LIST
    _install_deb_pkg ${DEBG_TMP_DIR}/chroot $DEBG_DEB_PKGS
    _run_in_root_system ${DEBG_TMP_DIR}/chroot $DEBG_EXE_LIST

    unset_chroot_operation ${DEBG_TMP_DIR}/chroot

    unset_trap
    set_trap "rm -rf $DEBG_TMP_DIR"

    if [ -z "$DEBG_JSON"]; then
        if [ -n "$DEBG_GPTTABLE" ]; then
            PART_TABLE="gpt"
        else
            PART_TABLE="msdos"
        fi
        DEBG_JSON="${DEBG_TMP_DIR}/diskhdr.json"
        echo "$DEFAULT_FSTAB_JSON" | sed "s/XXXTABLEXXX/${PART_TABLE}/g;s/XXXSWAPSIZEXXX/${DEBG_SWAP_SIZE}/g" > $DEBG_JSON
    fi

    _dest_format_mount_copy_n_set_trap

    # Grub installation

    if [ -z "$DEBG_BLKDEV" ]; then
        echo_die 1 "block device missing"
    fi

    setup_chroot_operation ${DEBG_TMP_DIR}/mnt

    _debg_install_tmp_grub_cfg ()
    {
        GRUB_CFG_PATH=${DEBG_TMP_DIR}/mnt/etc/default/grub.d/debg.cfg
        cat <<EOF > $GRUB_CFG_PATH
GRUB_DISABLE_OS_PROBER="true"
EOF
        sed -i 's/#GRUB_DISABLE_RECOVERY="true"/GRUB_DISABLE_RECOVERY="true"/' ${DEBG_TMP_DIR}/mnt/etc/default/grub
        cat <<EOF > ${DEBG_TMP_DIR}/mnt/boot/grub/device.map
(hd0) ${DEBG_BLKDEV}
EOF
    }

    if [ -n "$DEBG_GRUBEFI" ]; then
        _debg_install_tmp_grub_cfg

        echo_notify "Installing grub efi"
        if [ "$DEBG_CHROOT_ARCH" = "amd64" ]; then
            chroot ${DEBG_TMP_DIR}/mnt grub-install --removable --target=x86_64-efi --boot-directory=/boot --efi-directory=/boot --force
        else
            chroot ${DEBG_TMP_DIR}/mnt grub-install --removable --target=i386-efi --boot-directory=/boot --efi-directory=/boot --force
        fi
        chroot ${DEBG_TMP_DIR}/mnt update-grub || true
        echo_notify "grub installed"
    else
        _debg_install_tmp_grub_cfg

        echo_notify "Installing grub mbr"
        chroot ${DEBG_TMP_DIR}/mnt grub-install --force --target=i386-pc $DEBG_BLKDEV || true
        chroot ${DEBG_TMP_DIR}/mnt grub-mkconfig > ${DEBG_TMP_DIR}/mnt/boot/grub/grub.cfg || true
        echo_notify "grub installed"
    fi

    rm ${DEBG_TMP_DIR}/mnt/boot/grub/device.map $GRUB_CFG_PATH

    unset_chroot_operation ${DEBG_TMP_DIR}/mnt

    # End of grub installation

    echo_notify "Synchronizing cached write ..."
    $diskhdr_cmd $DEBG_JSON umount 0 $DEBG_DST_PATH ${DEBG_TMP_DIR}/mnt
    echo_notify "Cached write synchronization done"

    if [ -z "$DEBG_JSON_ARG" ]; then
        rm -f $DEBG_JSON
    fi

    rm -rf $DEBG_TMP_DIR

    unset_trap
}

_livedest_handle_block_or_file_n_set_trap ()
{
    DEBG_JSON="$(mktemp --suffix=_json)"
    echo $DEFAULT_LIVE_JSON > $DEBG_JSON

    if [ -e "$DEBG_DST_PATH" ]; then
        DEBG_DST_PATH="$(realpath $DEBG_DST_PATH)"
        if [ ! -b "$DEBG_DST_PATH" ]; then
            echo_die 1 "$DEBG_DST_PATH already exist"
        fi
        echo_notify "Flashing block device"
        set_trap "$diskhdr_cmd $DEBG_JSON umount 0 $DEBG_DST_PATH ${DEBG_TMP_DIR}/mnt; rm -rf $DEBG_TMP_DIR $DEBG_JSON"
    else
        echo_notify "Flashing image file"
        DEBG_LIVEDIR_SIZE="$(_echo_dir_ko_size ${DEBG_TMP_DIR}/live)"
        # Add 100000K(~100M) for grub
        DEBG_LIVEIMG_SIZE="$((($DEBG_LIVEDIR_SIZE * 110 / 100) + 100000))"
        truncate -s ${DEBG_LIVEIMG_SIZE}K $DEBG_DST_PATH
        set_trap "$diskhdr_cmd $DEBG_JSON umount 0 $DEBG_DST_PATH ${DEBG_TMP_DIR}/mnt; rm -rf $DEBG_TMP_DIR $DEBG_JSON $DEBG_DST_PATH"
    fi
}

_flash_pc_live ()
{
    _handle_dir_to_livesys_args "$@"

    echo_notify "Generating live system"

    DEBG_TMP_DIR="$(mktemp -d --suffix=_debg_livesys_dir)"
    mkdir ${DEBG_TMP_DIR}/live ${DEBG_TMP_DIR}/mnt

    # nb: _chroot_to_livesys_dir use set_trap
    if [ -n "$DEBG_SRC_PATH" ]; then
        _handle_flash_src_path_to_tmp_dir
        DEBG_CHROOT_KERNEL_VERSION=$(chroot ${DEBG_TMP_DIR}/chroot dpkg-query -f '${Depends}' -W "linux-image-$(dpkg --print-architecture)" | cut -f 1 -d' ' | sed "s/linux-image-//")
        _chroot_to_livesys_dir
    else
        ${DEBG_CURRENT_DIR}/debgen.sh pc-chroot -d ${DEBG_TMP_DIR}/chroot
        _chroot_to_livesys_dir
        rm -rf ${DEBG_TMP_DIR}/chroot
    fi

    diskhdr_cmd="${DEBG_CURRENT_DIR}/diskhdr.py"

    _livedest_handle_block_or_file_n_set_trap

    $diskhdr_cmd $DEBG_JSON format $DEBG_DST_PATH
    $diskhdr_cmd $DEBG_JSON mount 0 $DEBG_DST_PATH ${DEBG_TMP_DIR}/mnt

    rsync --modify-window=1 --update --recursive ${DEBG_TMP_DIR}/live/* ${DEBG_TMP_DIR}/mnt

    # Setup Boot
    grub-install --target=i386-pc --boot-directory=${DEBG_TMP_DIR}/mnt $DEBG_DST_PATH
    cat <<EOF > ${DEBG_TMP_DIR}/mnt/grub/grub.cfg
insmod ext2
set timeout=0
set root='hd0,msdos1'
linux /vmlinuz-${DEBG_CHROOT_KERNEL_VERSION} boot=live components persistence
initrd /initrd.img-${DEBG_CHROOT_KERNEL_VERSION}
boot
EOF
    # End of boot setup

    echo_notify "Synchronizing cached write ..."
    $diskhdr_cmd $DEBG_JSON umount 0 $DEBG_DST_PATH ${DEBG_TMP_DIR}/mnt
    echo_notify "Cached write synchronization done"

    rm -rf $DEBG_TMP_DIR $DEBG_JSON
    unset_trap
}

_handle_flash_iso_arg ()
{
    DEBG_LIVESYS_SYNOPSIS="\
Usage: $DEBG_NAME $DEBG_CMD_NAME [OPTIONS]
  Convert a chroot to a live system an flash it to a block device or a file.

OPTIONS:
  -a <PKG>, --add-package=<PKG> Add following debian package to the image
  -d <DST>, --destination <DST> Destination path
  -e <EXE>, --exec=<EXE>        Run executable into the new system
  -h, --help                    Display this help
  -i, --install-deb                  Add debian file to install
  -s <SRC>, --source=<SRC>      Source chroot directory
"

    OPTS=$(getopt -n "$DEBG_CMD_NAME" -o 'a:d:e:hi:s:' -l 'add-package:,destination:,exec:,help,install-deb:,source:' -- "$@")
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
        if [ ! -d "$DEBG_SRC_PATH" -a ! -f "$DEBG_SRC_PATH" ]; then
            echo "$DEBG_LIVESYS_SYNOPSIS"
            echo_die 1 "$DEBG_SRC_PATH chroot source is not a directory"
        fi
    fi
}

_flash_pc_iso ()
{
    _handle_flash_iso_arg "$@"

    echo_notify "Generating live system"
    DEBG_TMP_DIR="$(mktemp -d --suffix=_debg_livesys_dir)"
    mkdir ${DEBG_TMP_DIR}/live

    # nb: _chroot_to_livesys_dir use set_trap
    if [ -n "$DEBG_SRC_PATH" ]; then
        _handle_flash_src_path_to_tmp_dir
        DEBG_CHROOT_KERNEL_VERSION=$(chroot ${DEBG_TMP_DIR}/chroot dpkg-query -f '${Depends}' -W "linux-image-$(dpkg --print-architecture)" | cut -f 1 -d' ' | sed "s/linux-image-//")
        _chroot_to_livesys_dir
    else
        ${DEBG_CURRENT_DIR}/debgen.sh pc-chroot -d ${DEBG_TMP_DIR}/chroot
        DEBG_CHROOT_KERNEL_VERSION=$(chroot ${DEBG_TMP_DIR}/chroot dpkg-query -f '${Depends}' -W "linux-image-$(dpkg --print-architecture)" | cut -f 1 -d' ' | sed "s/linux-image-//")
        _chroot_to_livesys_dir
    fi

    # Setup Boot
    mkdir -p ${DEBG_TMP_DIR}/live/boot/grub
    cp ${DEBG_CURRENT_DIR}/grub_stage2_eltorito ${DEBG_TMP_DIR}/live/boot/grub/stage2_eltorito
    cat <<EOF > ${DEBG_TMP_DIR}/live/boot/grub/menu.lst
default 0
timeout 0
title live
kernel /vmlinuz-${DEBG_CHROOT_KERNEL_VERSION} boot=live components toram
initrd /initrd.img-${DEBG_CHROOT_KERNEL_VERSION}
boot
EOF
    # End of boot setup
    cp ${DEBG_TMP_DIR}/live/boot/grub/menu.lst ${DEBG_TMP_DIR}/live/boot/grub/grub.cfg

    genisoimage -o $DEBG_DST_PATH -R -J -b boot/grub/stage2_eltorito -no-emul-boot -boot-load-size 4 -boot-info-table ${DEBG_TMP_DIR}/live

    rm -rf ${DEBG_TMP_DIR}
}

# RPI Part

_flash_rpi ()
{
    _handle_flash_args "$@"

    DEBG_TMP_DIR="$(mktemp -d --suffix=_dbr_img_tmp_dir)"

    set_trap "unset_chroot_operation ${DEBG_TMP_DIR}/chroot; rm -rf $DEBG_TMP_DIR"

    if [ -n "$DEBG_SRC_PATH" ]; then
        mkdir ${DEBG_TMP_DIR}/chroot ${DEBG_TMP_DIR}/mnt
        echo_notify "Copying files ..."
        rsync -ad ${DEBG_SRC_PATH}/* ${DEBG_TMP_DIR}/chroot
        echo_notify "Files copy done"
    else
        mkdir ${DEBG_TMP_DIR}/mnt
        echo_notify "No source chroot provided generating a default one"
        ${DEBG_CURRENT_DIR}/debgen.sh rpi-chroot -d ${DEBG_TMP_DIR}/chroot
    fi

    if [ -n "$DEBG_ADD_PKG_LIST" -o -n "$DEBG_DEB_PKGS" -o -n "$DEBG_EXE_LIST" ]; then
        setup_chroot_operation ${DEBG_TMP_DIR}/chroot
        _chroot_add_pkg ${DEBG_TMP_DIR}/chroot $DEBG_ADD_PKG_LIST
        _install_deb_pkg ${DEBG_TMP_DIR}/chroot $DEBG_DEB_PKGS
        _run_in_root_system ${DEBG_TMP_DIR}/chroot $DEBG_EXE_LIST
        unset_chroot_operation ${DEBG_TMP_DIR}/chroot
    fi

    unset_trap

    if [ -z "$DEBG_JSON"]; then
        DEBG_JSON="${DEBG_TMP_DIR}/diskhdr.json"
        echo "$DEFAULT_FSTAB_RPI_JSON" > $DEBG_JSON
    fi

    _dest_format_mount_copy_n_set_trap

    echo_notify "Synchronizing cached write ..."
    $diskhdr_cmd $DEBG_JSON umount 0 $DEBG_DST_PATH ${DEBG_TMP_DIR}/mnt
    echo_notify "Cached write synchronization done"

    if [ -z "$DEBG_JSON_ARG" ]; then
        rm -f $DEBG_JSON
    fi

    rm -rf $DEBG_TMP_DIR

    unset_trap
}

_flash_rpi_live ()
{
    DEBG_TYPE="RPI"
    _handle_dir_to_livesys_args "$@"

    echo_notify "Generating live system"
    DEBG_TMP_DIR="$(mktemp -d --suffix=_debg_livesys_dir)"
    mkdir ${DEBG_TMP_DIR}/live ${DEBG_TMP_DIR}/mnt

    # nb: _chroot_to_livesys_dir use set_trap
    if [ -n "$DEBG_SRC_PATH" ]; then
        _handle_flash_src_path_to_tmp_dir
        _chroot_to_livesys_dir
    else
        ${DEBG_CURRENT_DIR}/debgen.sh rpi-chroot -d ${DEBG_TMP_DIR}/chroot
        _chroot_to_livesys_dir
        rm -rf ${DEBG_TMP_DIR}/chroot
    fi

    diskhdr_cmd="${DEBG_CURRENT_DIR}/diskhdr.py"

    _livedest_handle_block_or_file_n_set_trap

    $diskhdr_cmd $DEBG_JSON format $DEBG_DST_PATH
    $diskhdr_cmd $DEBG_JSON mount 0 $DEBG_DST_PATH ${DEBG_TMP_DIR}/mnt

    rsync --modify-window=1 --update --recursive ${DEBG_TMP_DIR}/live/* ${DEBG_TMP_DIR}/mnt

    # Setup Boot (TODO another method to retrieve kernel and initrd paths)
    mv ${DEBG_TMP_DIR}/mnt/initrd*v7+.img ${DEBG_TMP_DIR}/mnt/initrd7.img
    mv ${DEBG_TMP_DIR}/mnt/initrd*v7l+.img ${DEBG_TMP_DIR}/mnt/initrd7l.img
    mv ${DEBG_TMP_DIR}/mnt/initrd*v8+.img ${DEBG_TMP_DIR}/mnt/initrd8.img
    mv ${DEBG_TMP_DIR}/mnt/initrd*+.img ${DEBG_TMP_DIR}/mnt/initrd.img
    echo_notify "live-boot and initrd generation done"

    echo_notify "Setting up boot load"
    cat <<EOF > ${DEBG_TMP_DIR}/mnt/config.txt
kernel kernel7l.img
initramfs initrd7l.img followkernel
gpu_mem=320
dtoverlay=vc4-fkms-v3d
dtparam=audio=on
disable_overscan=1
EOF
    cat <<EOF > ${DEBG_TMP_DIR}/mnt/cmdline.txt
live-media=/dev/mmcblk0p1 rootwait cma=512M boot=live components persistence
EOF
    # End of boot setup

    echo_notify "Synchronizing cached write ..."
    $diskhdr_cmd $DEBG_JSON umount 0 $DEBG_DST_PATH ${DEBG_TMP_DIR}/mnt
    echo_notify "Cached write synchronization done"

    rm -rf $DEBG_TMP_DIR $DEBG_JSON
    unset_trap
}
