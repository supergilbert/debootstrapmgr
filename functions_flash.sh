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
            \"table\": \"gpt\",
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

DMGR_SIZE_1G=1048576

_handle_flash_args ()
{
    DMGR_PC_FLASHIMG_SYNOPSIS="\
Usage: $DMGR_NAME $DMGR_CMD_NAME [OPTIONS]
  Flash a chroot to a block device or a file.

OPTIONS:
  -d <DST>, --destination=<DST> Destination path
  -E, --efi                     Install grub-efi-amd64 instead of grub-pc
  -j <JSON>, --json <JSON>      Specify a json filesystem architecture
  -g, --gpt                     Setup an \"GPT\" partition table
                                instead of \"MSDOS\"
  -s <SRC>, --source=<SRC>      Chroot directory
  -w <SIZE>, --swap=<SIZE>      Swap size in Go (default 2Go)
  -h, --help                    Display this help
"

    OPTS=$(getopt -n "$DMGR_CMD_NAME" -o 'd:Egj:hs:S:w:' -l 'destination:,efi,gpt,json:,help,image-size:,source:,swap:' -- "$@")
    #Bad arguments
    if [ $? -ne 0 ]; then
        echo_err "Bad arguments.\n"
        exit 2
    fi
    eval set -- "$OPTS";
    while true; do
        case "$1" in
            '-d'|'--destination')
                shift
                DMGR_DST_PATH="$1"
                shift
                ;;
            '-E'|'--efi')
                shift
                DMGR_GRUBEFI="on"
                echo_notify "Setup system boot in UEFI mode"
                ;;
            '-j'|'--json')
                shift
                DMGR_JSON_ARG="$1"
                shift
                ;;
            '-s'|'--source')
                shift
                DMGR_CHROOT_DIR="$1"
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

    if [ ! -d "$DMGR_CHROOT_DIR" ]; then
        echo "$DMGR_PC_FLASHIMG_SYNOPSIS"
        echo_die 1 "$DMGR_CHROOT_DIR chroot source directory does not exist"
    fi

    if [ -z "$DMGR_SWAP_SIZE" ]; then
        # Default 2Go
        DMGR_SWAP_SIZE="2G"
    fi
    if [ "$DMGR_GRUBEFI" != "on" -a "$DMGR_GPTTABLE" = "on" ]; then
        echo_die 1 "Cannot install MBR on gpt table"
    fi

    diskhdr_cmd="${DMGR_CURRENT_DIR}/diskhdr.py"

    DMGR_TMP_DIR="$(mktemp -d --suffix=_dbr_img_tmp_dir)"

    . ${DMGR_CURRENT_DIR}/functions_chroot.sh

    if [ -n "$DMGR_JSON_ARG" ]; then
        DMGR_JSON="$DMGR_JSON_ARG"
    fi
}

_handle_dir_to_livesys_args ()
{
    DMGR_LIVESYS_SYNOPSIS="\
Usage: $DMGR_NAME $DMGR_CMD_NAME [OPTIONS]
  Convert a chroot to a live system an flash it to a block device or a file.

OPTIONS:
  -d <DST>, --destination <DST> Destination path
  -h, --help                    Display this help
  -s <SRC>, --source=<SRC>      Source chroot directory
  -p, --add-persistence=PATH    Add persistency on specified path
"

    OPTS=$(getopt -n "$DMGR_CMD_NAME" -o 'd:hp:s:' -l 'destination:,help,source:,add-persistence:' -- "$@")
    #Bad arguments
    if [ $? -ne 0 ]; then
        echo_err "Bad arguments.\n"
        exit 2
    fi
    eval set -- "$OPTS";
    while true; do
        case "$1" in
            '-d'|'--destination')
                shift
                DMGR_DST_PATH="$1"
                shift
                ;;
            '-h'|'--help')
                echo "$DMGR_LIVESYS_SYNOPSIS"
                exit 0
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

_echo_dir_ko_size ()
{
    du -s --apparent-size $1 2>/dev/null | sed 's/\([[:digit:]]\+\)[[:space:]]\+.*/\1/'
}

_echo_dir_mo_size ()
{
    echo "$((($(_echo_dir_ko_size $1) / 1024) + 1024))"
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

_pc_chroot_flash ()
{
    _handle_flash_args "$@"

    if [ -z "$DMGR_JSON"]; then
        if [ -n "$DMGR_GPTTABLE" ]; then
            PART_TABLE="gpt"
        else
            PART_TABLE="msdos"
        fi
        DMGR_JSON="$(mktemp --suffix=_json)"
        echo "$DEFAULT_FSTAB_JSON" | sed "s/XXXTABLEXXX/${PART_TABLE}/g;s/XXXSWAPSIZEXXX/${DMGR_SWAP_SIZE}/g" > $DMGR_JSON
    fi

    if [ ! -e "$DMGR_DST_PATH" ]; then
        echo_notify "$DMGR_DST_PATH not found generating image file"
        DMGR_IMAGE_TYPE="ON"
        # Adding 200Mo for grub
        DMGR_DISK_SIZE="$(($(_get_sys_min_size ${DMGR_CHROOT_DIR}) + $($diskhdr_cmd $DMGR_JSON minsize 0) + 200))"
        truncate -s ${DMGR_DISK_SIZE}M $DMGR_DST_PATH
    else
        DMGR_DST_PATH="$(realpath $DMGR_DST_PATH)"
        if [ ! -b "$DMGR_DST_PATH" ]; then
            echo_die 1 "$DMGR_DST_PATH already exist or is not a block device"
        fi
        # check block size
    fi

    if [ -n "$DMGR_JSON_ARG" ]; then
        set_trap "rm -f ${DMGR_TMP_DIR}/boot/grub/device.map $GRUB_CFG_PATH; unset_chroot_operation $DMGR_TMP_DIR; $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH $DMGR_TMP_DIR; rm -rf $DMGR_TMP_DIR $DMGR_JSON"
    else
        set_trap "rm -f ${DMGR_TMP_DIR}/boot/grub/device.map $GRUB_CFG_PATH; unset_chroot_operation $DMGR_TMP_DIR; $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH $DMGR_TMP_DIR; rm -rf $DMGR_TMP_DIR"
    fi

    $diskhdr_cmd $DMGR_JSON format $DMGR_DST_PATH
    DMGR_FSTAB_STR="$($diskhdr_cmd $DMGR_JSON fstab 0 $DMGR_DST_PATH)"
    $diskhdr_cmd $DMGR_JSON mount 0 $DMGR_DST_PATH $DMGR_TMP_DIR

    if [ -n "$DMGR_IMAGE_TYPE" ]; then
        DMGR_BLKDEV=$(losetup --raw | grep $DMGR_DST_PATH | cut -f 1 -d' ')
    else
        DMGR_BLKDEV=$DMGR_DST_PATH
    fi

    echo_notify "Copying files ..."
    rsync -ad ${DMGR_CHROOT_DIR}/* ${DMGR_TMP_DIR}
    echo_notify "Files copy done"

    # Grub installation

    . ${DMGR_CURRENT_DIR}/functions_chroot.sh

    setup_chroot_operation $DMGR_TMP_DIR

    echo "$DMGR_FSTAB_STR" > ${DMGR_TMP_DIR}/etc/fstab

    _dmgr_install_tmp_grub_cfg ()
    {
        GRUB_CFG_PATH=${DMGR_TMP_DIR}/etc/default/grub.d/dmgr.cfg
        cat <<EOF > $GRUB_CFG_PATH
GRUB_DISABLE_OS_PROBER="true"
EOF
        sed -i 's/#GRUB_DISABLE_RECOVERY="true"/GRUB_DISABLE_RECOVERY="true"/' ${DMGR_TMP_DIR}/etc/default/grub
        cat <<EOF > ${DMGR_TMP_DIR}/boot/grub/device.map
(hd0) $DMGR_BLKDEV
EOF
    }

    if [ -n "$DMGR_GRUBEFI" ]; then
        chroot $DMGR_TMP_DIR apt update
        chroot $DMGR_TMP_DIR apt -y install grub-efi-amd64 grub-efi-amd64-signed

        _dmgr_install_tmp_grub_cfg

        echo_notify "Installing grub"
        chroot $DMGR_TMP_DIR grub-install --removable --target=x86_64-efi --boot-directory=/boot --efi-directory=/boot --force || true
        chroot $DMGR_TMP_DIR update-grub || true
        echo_notify "grub installed"
    else
        chroot $DMGR_TMP_DIR apt update
        chroot $DMGR_TMP_DIR apt -y install grub-pc

        _dmgr_install_tmp_grub_cfg

        echo_notify "Installing grub"
        chroot $DMGR_TMP_DIR grub-install --force --target=i386-pc $DMGR_BLKDEV || true
        chroot $DMGR_TMP_DIR grub-mkconfig -o /boot/grub/grub.cfg || true
        echo_notify "grub installed"
    fi

    rm ${DMGR_TMP_DIR}/boot/grub/device.map $GRUB_CFG_PATH

    unset_chroot_operation $DMGR_TMP_DIR

    $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH $DMGR_TMP_DIR

    rm -rf $DMGR_TMP_DIR

    if [ -z "$DMGR_JSON_ARG" ]; then
        rm -f $DMGR_JSON
    fi

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

    . ${DMGR_CURRENT_DIR}/functions_chroot.sh

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
        chroot ${2}/tmpdir update-initramfs -u -k all
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

    mv ${2}/tmpdir/boot/* ${2}/

    mkdir ${2}/live
    mksquashfs ${2}/tmpdir ${2}/live/filesystem.squashfs
    rm -rf ${2}/tmpdir
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

    rsync -ad ${DMGR_TMP_DIR}/live/* ${DMGR_TMP_DIR}/mnt

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

    if [ -z "$DMGR_JSON"]; then
        if [ -n "$DMGR_GPTTABLE" ]; then
            PART_TABLE="gpt"
        else
            PART_TABLE="msdos"
        fi
        DMGR_JSON="$(mktemp --suffix=_json)"
        echo "$DEFAULT_FSTAB_RPI_JSON" | sed "s/XXXTABLEXXX/${PART_TABLE}/g;s/XXXSWAPSIZEXXX/${DMGR_SWAP_SIZE}/g" > $DMGR_JSON
    fi

    if [ ! -e "$DMGR_DST_PATH" ]; then
        echo_notify "$DMGR_DST_PATH not found generating image file"
        # DMGR_IMAGE_TYPE="ON"
        DMGR_DISK_SIZE="$(($(_get_sys_min_size ${DMGR_CHROOT_DIR}) + $($diskhdr_cmd $DMGR_JSON minsize 0)))"
        DMGR_DISK_SIZE="$(($DMGR_DISK_SIZE * 110 / 100))"
        truncate -s ${DMGR_DISK_SIZE}M $DMGR_DST_PATH
    else
        DMGR_DST_PATH="$(realpath $DMGR_DST_PATH)"
        if [ ! -b "$DMGR_DST_PATH" ]; then
            echo_die 1 "$DMGR_DST_PATH already exist or is not a block device"
        fi
        # check block size
    fi

    if [ -n "$DMGR_JSON_ARG" ]; then
        set_trap "rm -f ${DMGR_TMP_DIR}/boot/grub/device.map $GRUB_CFG_PATH; unset_chroot_operation $DMGR_TMP_DIR; $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH $DMGR_TMP_DIR; rm -rf $DMGR_TMP_DIR $DMGR_JSON"
    else
        set_trap "rm -f ${DMGR_TMP_DIR}/boot/grub/device.map $GRUB_CFG_PATH; unset_chroot_operation $DMGR_TMP_DIR; $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH $DMGR_TMP_DIR; rm -rf $DMGR_TMP_DIR"
    fi

    $diskhdr_cmd $DMGR_JSON format $DMGR_DST_PATH
    DMGR_FSTAB_STR="$($diskhdr_cmd $DMGR_JSON fstab 0 $DMGR_DST_PATH)"
    $diskhdr_cmd $DMGR_JSON mount 0 $DMGR_DST_PATH $DMGR_TMP_DIR

    # if [ -n "$DMGR_IMAGE_TYPE" ]; then
    #     DMGR_BLKDEV=$(losetup --raw | grep $DMGR_DST_PATH | cut -f 1 -d' ')
    # else
    #     DMGR_BLKDEV=$DMGR_DST_PATH
    # fi

    echo_notify "Copying files ..."
    rsync -ad ${DMGR_CHROOT_DIR}/* ${DMGR_TMP_DIR}
    echo_notify "Files copy done"

    echo "$DMGR_FSTAB_STR" > ${DMGR_TMP_DIR}/etc/fstab

    $diskhdr_cmd $DMGR_JSON umount 0 $DMGR_DST_PATH $DMGR_TMP_DIR

    rm -rf $DMGR_TMP_DIR

    if [ -z "$DMGR_JSON_ARG" ]; then
        rm -f $DMGR_JSON
    fi

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
