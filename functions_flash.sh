#!/bin/sh

. ${DMGR_CURRENT_DIR}/functions.sh

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

umount_bootsys_type_image ()
{
    _IMG_PATH=$1
    _MOUNT_PATH=$2

    umount ${_MOUNT_PATH}/boot "$_MOUNT_PATH"
    kpartx -d "$_IMG_PATH"
}

# PC Part

umount_sys_type_image ()
{
    _IMG_PATH=$1
    _MOUNT_PATH=$2

    umount "$_MOUNT_PATH"
    kpartx -d "$_IMG_PATH"
}

_handle_pc_flash_img ()
{
    DMGR_PC_FLASHIMG_SYNOPSIS="\
Usage: $DMGR_NAME $DMGR_CMD_NAME [OPTIONS]
  Generate a RPI Image.

OPTIONS:
  -d <DEST>, --destination <DEST>   Destination file
  -E, --efi                         Install grub-efi-amd64 instead of grub-pc
  -M, --msdos                       Setup an \"MSDOS\" partition table
                                    instead of \"GPT\"
  -s <SRC>, --source=<SRC>          Chroot directory
  -w <SIZE>, --swap=<SIZE>          Swap size in Giga octet (default 2Go)
  -h, --help                        Display this help
"

    OPTS=$(getopt -n "$DMGR_CMD_NAME" -o 'd:EhMs:w:' -l 'destination:,efi,help,msdos,source:,swap:' -- "$@")
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
                DMGR_IMG_PATH="$1"
                shift
                ;;
            '-E'|'--efi')
                shift
                DMGR_GRUBEFI="on"
                echo_notify "Setup system boot in UEFI mode"
                ;;
            '-s'|'--source')
                shift
                DMGR_CHROOT_DIR="$1"
                shift
                ;;
            '-M'|'--msdos')
                shift
                DMGR_MSDOSTABLE="on"
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

    if [ -z "$DMGR_IMG_PATH" ]; then
        echo "$DMGR_PC_FLASHIMG_SYNOPSIS"
        echo_die 1 "Destination is mandatory"
    fi

    if [ ! -d "$DMGR_CHROOT_DIR" ]; then
        echo "$DMGR_PC_FLASHIMG_SYNOPSIS"
        echo_die 1 "$DMGR_CHROOT_DIR chroot source directory does not exist"
    fi

    if [ -z "$DMGR_SWAP_SIZE" ]; then
        # Default 2Go
        DMGR_SWAP_SIZE="2"
    fi
}



DMGR_SIZE_1G=1048576

_dmgr_pc_image_part_n_mount_mbr_type ()
{
    if [ "$1" != "gpt" -a "$1" != "msdos" ]; then
        echo_die 1 "Need gpt or msdos as argument"
    fi
    DMGR_CHROOT_SIZE="$(du -s ${DMGR_CHROOT_DIR} 2>/dev/null | sed 's/\([[:digit:]]\+\)[[:space:]]\+.*/\1/')"
    DMGR_IMG_SIZE="$((((${DMGR_SWAP_SIZE} * ${DMGR_SIZE_1G}) + ${DMGR_CHROOT_SIZE}) * 110 / 100))"
    truncate -s ${DMGR_IMG_SIZE}K "$DMGR_IMG_PATH"
    DMGR_SYS_PART_START="$((1 + ${DMGR_SWAP_SIZE}))"
    if [ "$1" = "msdos" ]; then
        parted -s $DMGR_IMG_PATH mktable msdos mkpart primary linux-swap 0% 1G mkpart primary ext4 1G 100% set 2 boot on
    else
        parted -s $DMGR_IMG_PATH mktable gpt mkpart swap linux-swap 0% 1G mkpart system ext4 1G 100% set 2 boot on
    fi
    KPARTX_ADD_INFO="$(kpartx -asv $DMGR_IMG_PATH | sed 's/add map \([^[:blank:]]\+\)[[:blank:]]\+.*/\1/')"
    SWAP_PART=/dev/mapper/$(echo "$KPARTX_ADD_INFO" | grep "p1$")
    SYS_PART=/dev/mapper/$(echo "$KPARTX_ADD_INFO" | grep "p2$")
    LOOPDEV=/dev/$(echo "$KPARTX_ADD_INFO" | grep "p1$" | cut -dp -f -2)
    mkswap $SWAP_PART
    mkfs.ext4 -F $SYS_PART
    mount $SYS_PART $DMGR_TMP_DIR
}

_dmgr_pc_image_part_n_mount_uefi_type ()
{
    if [ "$1" != "gpt" -a "$1" != "msdos" ]; then
        echo_die 1 "Need gpt or msdos as argument"
    fi
    DMGR_CHROOT_SIZE="$(du -s ${DMGR_CHROOT_DIR} 2>/dev/null | sed 's/\([[:digit:]]\+\)[[:space:]]\+.*/\1/')"
    DMGR_TMP_SIZE="$(du -s ${DMGR_CHROOT_DIR}/boot 2>/dev/null | sed 's/\([[:digit:]]\+\)[[:space:]]\+.*/\1/')"
    DMGR_SYS_SIZE="$((${DMGR_CHROOT_SIZE} - ${DMGR_TMP_SIZE}))"
    DMGR_TMP_SIZE="$((1 * ${DMGR_SIZE_1G}))"
    DMGR_TMP_SIZE="$(((${DMGR_SWAP_SIZE} * ${DMGR_SIZE_1G}) + ${DMGR_TMP_SIZE}))"
    DMGR_IMG_SIZE="$(((${DMGR_TMP_SIZE} + ${DMGR_SYS_SIZE}) * 110 / 100))"

    echo_notify "Generation image file $DMGR_IMG_PATH of ${DMGR_IMG_SIZE}Ko"

    truncate -s ${DMGR_IMG_SIZE}K "$DMGR_IMG_PATH"
    DMGR_SYS_PART_START="$((1 + ${DMGR_SWAP_SIZE}))"
    if [ "$1" = "msdos" ]; then
        parted -s $DMGR_IMG_PATH mktable msdos mkpart primary fat32 0% 1G set 1 boot on set 1 esp on mkpart primary linux-swap 1G ${DMGR_SYS_PART_START}G mkpart primary ext4 ${DMGR_SYS_PART_START}G 100%
    else
        parted -s $DMGR_IMG_PATH mktable gpt mkpart boot fat32 0% 1G set 1 boot on set 1 esp on mkpart swap linux-swap 1G ${DMGR_SYS_PART_START}G mkpart system ext4 ${DMGR_SYS_PART_START}G 100%
    fi
    KPARTX_ADD_INFO="$(kpartx -asv $DMGR_IMG_PATH | sed 's/add map \([^[:blank:]]\+\)[[:blank:]]\+.*/\1/')"
    BOOT_PART=/dev/mapper/$(echo "$KPARTX_ADD_INFO" | grep "p1$")
    SWAP_PART=/dev/mapper/$(echo "$KPARTX_ADD_INFO" | grep "p2$")
    SYS_PART=/dev/mapper/$(echo "$KPARTX_ADD_INFO" | grep "p3$")
    LOOPDEV=/dev/$(echo "$KPARTX_ADD_INFO" | grep "p1$" | cut -dp -f -2)
    mkfs.vfat -F32 $BOOT_PART
    mkswap $SWAP_PART
    mkfs.ext4 -F $SYS_PART
    mount $SYS_PART $DMGR_TMP_DIR
    mkdir ${DMGR_TMP_DIR}/boot
    mount $BOOT_PART ${DMGR_TMP_DIR}/boot
}

pc_dir_to_default_img ()
{
    _handle_pc_flash_img "$@"

    DMGR_TMP_DIR="$(mktemp -d --suffix=_dbr_img_tmp_dir)"
    if [ -n "$DMGR_GRUBEFI" ]; then

        set_trap "unset_chroot_mountpoint $DMGR_TMP_DIR; umount_bootsys_type_image $DMGR_IMG_PATH $DMGR_TMP_DIR; rm -rf $DMGR_TMP_DIR; rm -f $DMGR_IMG_PATH"

        if [ -n "$DMGR_MSDOSTABLE" ]; then
            _dmgr_pc_image_part_n_mount_uefi_type msdos
        else
            _dmgr_pc_image_part_n_mount_uefi_type gpt
        fi

    else

        set_trap "unset_chroot_mountpoint $DMGR_TMP_DIR; umount_sys_type_image $DMGR_IMG_PATH $DMGR_TMP_DIR; rm -rf $DMGR_TMP_DIR; rm -f $DMGR_IMG_PATH"

        if [ -n "$DMGR_MSDOSTABLE" ]; then
            _dmgr_pc_image_part_n_mount_mbr_type msdos
        else
            _dmgr_pc_image_part_n_mount_mbr_type gpt
        fi

    fi

    . ${DMGR_CURRENT_DIR}/functions_chroot.sh

    echo_notify "Copying files ..."
    rsync -ad ${DMGR_CHROOT_DIR}/* ${DMGR_TMP_DIR}
    echo_notify "Files copy done"

    cat <<EOF > ${DMGR_TMP_DIR}/etc/fstab
# <file system> <mount point> <type> <options>         <dump> <pass>
proc            /proc         proc   defaults          0      0
/dev/sda3       /             ext4   errors=remount-ro 0      1
/dev/sda2       none          swap   sw                0      0
/dev/sda1       /boot         vfat   errors=remount-ro 0      2
EOF

    # Grub installation

    . ${DMGR_CURRENT_DIR}/functions_chroot.sh

    _dmgr_install_tmp_grub_cfg ()
    {
        GRUB_CFG_PATH=${DMGR_TMP_DIR}/etc/default/grub.d/dmgr.cfg
        cat <<EOF > $GRUB_CFG_PATH
GRUB_DISABLE_OS_PROBER="true"
EOF
        sed -i 's/#GRUB_DISABLE_RECOVERY="true"/GRUB_DISABLE_RECOVERY="true"/' ${DMGR_TMP_DIR}/etc/default/grub
        cat <<EOF > ${DMGR_TMP_DIR}/boot/grub/device.map
(hd0) $LOOPDEV
EOF
    }

    setup_chroot_mountpoint $DMGR_TMP_DIR


    if [ -z "$DMGR_GRUBEFI" ]; then

        # Grub with MBR

        chroot $DMGR_TMP_DIR apt update
        chroot $DMGR_TMP_DIR apt -y install grub-pc

        _dmgr_install_tmp_grub_cfg

        chroot $DMGR_TMP_DIR grub-install --force --target=i386-pc $LOOPDEV || true
        chroot $DMGR_TMP_DIR grub-mkconfig -o /boot/grub/grub.cfg || true

        rm ${DMGR_TMP_DIR}/boot/grub/device.map $GRUB_CFG_PATH

        unset_chroot_mountpoint $DMGR_TMP_DIR

        umount_sys_type_image $DMGR_IMG_PATH $DMGR_TMP_DIR

    else

        # Grub with EFI

        chroot $DMGR_TMP_DIR apt update
        chroot $DMGR_TMP_DIR apt -y install grub-efi-amd64

        _dmgr_install_tmp_grub_cfg

        chroot $DMGR_TMP_DIR grub-install --force --target=x86_64-efi --efi-directory=/boot --bootloader-id=BOOT --removable || true
        cp ${DMGR_TMP_DIR}/boot/EFI/BOOT/grubx64.efi ${DMGR_TMP_DIR}/boot/EFI/BOOT/BOOTx64.efi
        chroot $DMGR_TMP_DIR update-grub || true

        rm ${DMGR_TMP_DIR}/boot/grub/device.map $GRUB_CFG_PATH

        unset_chroot_mountpoint $DMGR_TMP_DIR

        umount_bootsys_type_image $DMGR_IMG_PATH $DMGR_TMP_DIR

    fi

    rm -rf $DMGR_TMP_DIR

    unset_trap
}

# RPI Part

DMGR_RPI_DEFAULT_BOOT_SIZE="$((500 * 1024))"

rpi_create_default_partitions ()
{
    echo_notify "Partitioning $1 ..."
    parted -s $1 mktable msdos mkpart primary fat32 0% ${DMGR_RPI_DEFAULT_BOOT_SIZE}K mkpart primary ext4 2G 100% print
    echo_notify "Partition $1 done\n"
}

rpi_create_default_filesystems ()
{
    echo_notify "Creating filesystems ..."
    mkfs.fat -F32 $1
    mkfs.ext4 -F $2
    echo_notify "Filesystems created\n"
}

rpi_create_n_mount_empty_default_image ()
{
    _IMG_PATH=$1
    _MOUNT_PATH=$2

    rpi_create_default_partitions "$_IMG_PATH"

    _KPARTX_ADD_INFO="$(kpartx -asv $_IMG_PATH | sed 's/add map \([^[:blank:]]\+\)[[:blank:]]\+.*/\1/')"
    _BOOT_PART=/dev/mapper/$(echo "$_KPARTX_ADD_INFO" | grep "p1$")
    _SYS_PART=/dev/mapper/$(echo "$_KPARTX_ADD_INFO" | grep "p2$")

    rpi_create_default_filesystems "$_BOOT_PART" "$_SYS_PART"

    mount "$_SYS_PART" "$_MOUNT_PATH"
    mkdir ${_MOUNT_PATH}/boot
    mount "$_BOOT_PART" ${_MOUNT_PATH}/boot
}

rpi_gen_dirsize_img_file ()
{
    local DMGR_DIR_PATH=$1
    local DMGR_FILE_PATH=$2
    local DMGR_TOTAL_SIZE="$(du -s ${DMGR_DIR_PATH} 2>/dev/null | sed 's/\([[:digit:]]\+\)[[:space:]]\+.*/\1/')"
    local DMGR_BOOT_SIZE="$(du -s ${DMGR_DIR_PATH}/boot 2>/dev/null | sed 's/\([[:digit:]]\+\)[[:space:]]\+.*/\1/')"
    local DMGR_SYS_SIZE="$((${DMGR_TOTAL_SIZE} - ${DMGR_BOOT_SIZE}))"
    local DMGR_IMG_SIZE="$(((${DMGR_RPI_DEFAULT_BOOT_SIZE} + ${DMGR_SYS_SIZE}) * 110 / 100))"
    echo_notify "Generation image file $DMGR_FILE_PATH of ${DMGR_IMG_SIZE}Ko"
    truncate -s ${DMGR_IMG_SIZE}K "$DMGR_FILE_PATH"
}

DMGR_FLASHER_SYNOPSIS="Usage: $DMGR_NAME $DMGR_CMD_NAME <SRC> <DST>"

_rpi_dir_to_img ()
{
    if [ 2 -ne "$#" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "rpi_dir_to_img need 2 arguments."
    fi
    if [ ! -d "$1" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need a directory as first argument"
    fi
    if [ -z "$2" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need a file path as second argument"
    fi

    DMGR_CHROOT_DIR=$1
    DMGR_IMG_PATH=$2

    if [ ! chroot $DMGR_CHROOT_DIR dpkg -l raspberrypi-bootloader raspberrypi-kernel ]; then
        echo_die "/!\ raspberrypi-bootloader raspberrypi-kernel pkg not found"
    fi

    set_trap "umount_bootsys_type_image $_DMGR_IMG_PATH $_DMGR_TMP_DIR; rm -rf $_DMGR_TMP_DIR; rm -f $_DMGR_IMG_PATH"

    DMGR_DIR_PATH=$1
    DMGR_FILE_PATH=$2
    DMGR_TOTAL_SIZE="$(du -s ${DMGR_DIR_PATH} 2>/dev/null | sed 's/\([[:digit:]]\+\)[[:space:]]\+.*/\1/')"
    DMGR_BOOT_SIZE="$(du -s ${DMGR_DIR_PATH}/boot 2>/dev/null | sed 's/\([[:digit:]]\+\)[[:space:]]\+.*/\1/')"
    DMGR_SYS_SIZE="$((${DMGR_TOTAL_SIZE} - ${DMGR_BOOT_SIZE}))"
    DMGR_IMG_SIZE="$(((2097152 + ${DMGR_SYS_SIZE}) * 110 / 100))"
    echo_notify "Generation image file $DMGR_FILE_PATH of ${DMGR_IMG_SIZE}Ko"
    truncate -s ${DMGR_IMG_SIZE}K "$DMGR_FILE_PATH"

    DMGR_TMP_DIR="$(mktemp -d --suffix=_dbr_img_tmp_dir)"

    rpi_create_n_mount_empty_default_image $DMGR_IMG_PATH $DMGR_TMP_DIR

    echo_notify "Copying files ..."
    cp -ra ${DMGR_CHROOT_DIR}/* ${DMGR_TMP_DIR}/

    umount_bootsys_type_image $DMGR_IMG_PATH $DMGR_TMP_DIR
    rm -rf $DMGR_TMP_DIR

    unset_trap

    echo_notify "Files copy done"
}

_rpi_img_to_partclone ()
{
    if [ 2 -ne "$#" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need 2 arguments."
    fi
    if [ ! -f "$1" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need an image as first argument"
    fi
    if [ -z "$2" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need a file path as second argument"
    fi
    if [ -f "$2" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Destination file already exist"
    fi

    DMGR_IMG_FILE="$1"
    DMGR_IMG_DST="$2"

    DMGR_TMP_DIR="$(mktemp -d --suffix=_dbr_tmp_dir)"

    if [ -n "$DMGR_EXE_LIST" ]; then
        check_exe_list $DMGR_EXE_LIST
    fi

    cleanup_force ()
    {
        rm -rf "$DMGR_TMP_DIR"
        kpartx -d "$DMGR_IMG_FILE"
    }

    set_trap "cleanup_force"

    KPARTX_ADD_INFO="$(kpartx -asv $DMGR_IMG_FILE | sed 's/add map \([^[:blank:]]\+\)[[:blank:]]\+.*/\1/')"
    BOOT_PART=/dev/mapper/$(echo "$KPARTX_ADD_INFO" | grep "p1$")
    SYS_PART=/dev/mapper/$(echo "$KPARTX_ADD_INFO" | grep "p2$")

    partclone.fat32 -d -c -s "$BOOT_PART" -o ${DMGR_TMP_DIR}/boot_part.img
    partclone.ext4 -d -c -s "$SYS_PART" -o ${DMGR_TMP_DIR}/sys_part.img

    kpartx -dv "$DMGR_IMG_FILE"

    echo_notify "Tar partclone images ..."
    tar -C "$DMGR_TMP_DIR" -czf "$DMGR_IMG_DST" ./
    echo_notify "Tar partclone images done"

    rm -rf "$DMGR_TMP_DIR"

    unset_trap
}

_rpi_partclone_to_blk ()
{
    if [ 2 -ne "$#" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need 2 arguments."
    fi
    if [ ! -f "$1" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need a partclone as first argument"
    fi
    DMGR_BLOCKDEV="$2"
    if [ ! -b "$DMGR_BLOCKDEV" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need a block device as second argument"
    fi

    DMGR_IMG_FILE="$1"

    if [ -n "$DMGR_EXE_LIST" ]; then
        check_exe_list $DMGR_EXE_LIST
    fi

    DMGR_TMP_DIR="$(mktemp -d --suffix=_dbr_tmp_dir)"

    set_trap "rm -rf $DMGR_TMP_DIR"

    echo_notify "Untar partclone ..."
    tar -C "$DMGR_TMP_DIR" -xf "$DMGR_IMG_FILE"
    echo_notify "Untar partclone done"

    rpi_create_default_partitions $DMGR_BLOCKDEV
    DMGR_BOOT_PART="$(wait_blk_path $DMGR_BLOCKDEV 1)"
    DMGR_SYS_PART="$(wait_blk_path $DMGR_BLOCKDEV 2)"
    rpi_create_default_filesystems "$DMGR_BOOT_PART" "$DMGR_SYS_PART"

    echo_notify "Cloning boot partition"
    partclone.fat32 -d -r -s ${DMGR_TMP_DIR}/boot_part.img -o $DMGR_BOOT_PART
    echo_notify "Cloning system partition"
    partclone.ext4 -d -r -s ${DMGR_TMP_DIR}/sys_part.img -o $DMGR_SYS_PART
    echo_notify "Cloning done"

    echo_notify "Resizing system partition"
    fsck.ext4 -f $DMGR_SYS_PART
    resize2fs $DMGR_SYS_PART
    echo_notify "Resizing system partition done"

    rm -rf $DMGR_TMP_DIR/*

    sync

    set_trap "umount $DMGR_SYS_PART"

    mount $DMGR_SYS_PART $DMGR_TMP_DIR
    cat <<EOF >  ${DMGR_TMP_DIR}/etc/fstab
#<file system> <mount point> <type> <options>                 <dump> <pass>
/dev/mmcblk0p1 /boot         vfat   errors=remount-ro,noatime 0      2
/dev/mmcblk0p2 /             ext4   errors=remount-ro,noatime 0      1
EOF
    umount $DMGR_SYS_PART

    rmdir $DMGR_TMP_DIR

    unset_trap
}

_rpi_dir_to_partclone ()
{
    if [ 2 -ne "$#" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need 2 arguments."
    fi
    if [ ! -d "$1" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need a directory as first argument"
    fi
    if [ -z "$2" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need a file path as second argument"
    fi
    if [ -f "$2" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Destination file already exist"
    fi

    DMGR_TMP_IMG="$(mktemp --suffix=_dbr_tmp_img)"

    _rpi_dir_to_img $1 $DMGR_TMP_IMG

    _rpi_img_to_partclone $DMGR_TMP_IMG $2

    rm $DMGR_TMP_IMG
}

_rpi_dir_to_blk ()
{
    if [ 2 -ne "$#" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need 2 arguments."
    fi
    if [ ! -d "$1" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need a directory as first argument"
    fi
    if [ -z "$2" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need a file path as second argument"
    fi
    if [ ! -b "$2" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Destination file must be a block device"
    fi

    DMGR_TMP_IMG="$(mktemp --suffix=_dbr_tmp_partclone_img)"

    _rpi_dir_to_partclone $1 $DMGR_TMP_IMG
    _rpi_partclone_to_blk $DMGR_TMP_IMG $2

    rm $DMGR_TMP_IMG
}

_rpi_dir_to_livesys_dir ()
{
    if [ 2 -ne "$#" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need 2 arguments."
    fi
    if [ ! -d "$1" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need a directory as first argument"
    fi
    if [ -z "$2" ]; then
        echo "$DMGR_FLASHER_SYNOPSIS"
        echo_die 1 "Need a directory path as second argument"
    fi

    if [ ! -d "$2" ]; then
        mkdir -p ${2}/tmpdir
    else
        echo_notify "File operation on an existing directory"
    fi

    echo_notify "Generating live directory in $2"

    echo_notify "Copying chroot $1 to $2 build directory ..."
    rsync -ad ${1}/* ${2}/tmpdir/
    echo_notify "Copy done"

    echo_notify "Generating live-boot and initrd ..."
    INITRAMFS_GEN_SH=$(mktemp --suffix=_initramfs_gen.sh)
    cat <<EOF > $INITRAMFS_GEN_SH
#!/bin/sh -ex

for kversion in \$(ls /lib/modules); do
    mkinitramfs -o /boot/initrd-\${kversion}.img \$kversion
done
EOF
    chmod +x $INITRAMFS_GEN_SH
    . ${DMGR_CURRENT_DIR}/functions_chroot.sh
    _chroot_exec -a live-boot -e $INITRAMFS_GEN_SH -d ${2}/tmpdir
    rm $INITRAMFS_GEN_SH

    mv ${2}/tmpdir/boot/initrd*v7+.img ${2}/tmpdir/boot/initrd7.img
    mv ${2}/tmpdir/boot/initrd*v7l+.img ${2}/tmpdir/boot/initrd7l.img
    mv ${2}/tmpdir/boot/initrd*v8+.img ${2}/tmpdir/boot/initrd8.img
    mv ${2}/tmpdir/boot/initrd*+.img ${2}/tmpdir/boot/initrd.img
    echo_notify "live-boot and initrd generation done"

    echo_notify "Setting up boot load"
    cat <<EOF > ${2}/tmpdir/boot/config.txt
kernel kernel7l.img
initramfs initrd7l.img followkernel
gpu_mem=320
dtoverlay=vc4-fkms-v3d
dtparam=audio=on
disable_overscan=1
EOF
#     cat <<EOF > ${2}/tmpdir/boot/cmdline.txt
# live-media=/dev/mmcblk0p1 rootwait cma=512M boot=live components persistence-path=/live/home_persistence persistence-method=home-rw
# EOF
    cat <<EOF > ${2}/tmpdir/boot/cmdline.txt
live-media=/dev/mmcblk0p1 rootwait cma=512M boot=live components
EOF

#     # Remount rw live medium
#     cat <<EOF > ${2}/tmpdir/lib/systemd/system/remount-medium.service
# [Unit]
# Description=Remount rw the medium
# After=systemd-udevd.service

# [Service]
# ExecStart=/usr/bin/mount -o remount,sync,umask=0000 /run/live/medium
# Type=oneshot
# RemainAfterExit=true

# [Install]
# WantedBy=multi-user.target
# EOF

    echo_notify "Setting up live system file architecture"
    mv ${2}/tmpdir/boot/* ${2}/
    mkdir ${2}/live
    # touch ${2}/live/home_persistence
    # mv ${2}/tmpdir/home ${2}/live/
    # ln -s /run/live/medium/live/home ${2}/tmpdir/home
    mksquashfs ${2}/tmpdir ${2}/live/filesystem.squashfs
    rm -rf ${2}/tmpdir

    echo_notify "live directory generation done"
}
