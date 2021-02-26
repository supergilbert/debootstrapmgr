#!/bin/sh

set -e

if [ -n "$DEBUG_DMGR" ]; then
    set -x
fi

DMGR_CURRENT_DIR=$(dirname $(realpath $0))

. ${DMGR_CURRENT_DIR}/functions.sh

if [ "$(id -u)" != "0" ]; then
    echo_die 1 "Need root privilegies"
fi

if [ -z "$DMGR_NAME" ]; then
    DMGR_NAME=$(basename $0)
fi

DMGR_SYNOPSIS="\
usage: $DMGR_NAME <command> [<args>]

A tool to flash, generate or prepare debian chroot for RPI and PC architecture.

Commands:

  help  Display this help

Chroot commands

  pc-debootstrap  Use debootstrap to generate a default pc chroot
  rpi-debootstrap Use debootstrap to generate a default rpi chroot
                  (Need armhf architecture dpkg --print-foreign-architectures)
  chroot-exec     Exec command in a chroot disabling its service start
  chroot          Run chroot (in the specified directory) and disabling its
                  service start

Flash commands (/!\ caution in what you are flashing)
  (Following commands use a default RPI and PC partition schema.
   Searching for a way to bind the chroot directory with debian bootload
   mechanism, partition table and fstab)

  pc-flashchroot-to-img        Flash a pc chroot to an raw image file
  rpi-flashchroot-to-blk       Flash a rpi chroot to an raw image file
  rpi-flashchroot-to-partclone Flash a rpi chroot to partclones tgz image
  rpi-flashpartclone-to-blk    Flash a partclones tgz image to a block device
  rpi-chroot-to-livedir        Generate filesquash live system directory from
                               chroot (with home directory linked from medium
                               in rw mode)
"

if [ $# -lt 1 ]; then
    echo "$DMGR_SYNOPSIS"
    echo_die 1 "Need arguments"
fi

DMGR_CMD_NAME=$1

case $DMGR_CMD_NAME in
    "pc-debootstrap")
        shift

        . ${DMGR_CURRENT_DIR}/functions_chroot.sh

        _debootstrap_pc "$@"

        echo_notify "PC chroot generated at $DMGR_CHROOT_DIR"
        ;;

    "rpi-debootstrap")
        shift

        . ${DMGR_CURRENT_DIR}/functions_chroot.sh

        _debootstrap_rpi "$@"

        echo_notify "RPI chroot generated at $DMGR_CHROOT_DIR"
        ;;

    "chroot-exec")
        shift

        . ${DMGR_CURRENT_DIR}/functions_chroot.sh

        _chroot_exec "$@"

        echo_notify "Chroot executions done"
        ;;

    "chroot")
        shift

        . ${DMGR_CURRENT_DIR}/functions_chroot.sh

        _chroot "$@"
        ;;

    "pc-flashchroot-to-img")
        shift

        . ${DMGR_CURRENT_DIR}/functions_flash.sh

        pc_dir_to_default_img "$@"

        echo_notify "PC image done at $DMGR_IMG_PATH"
        ;;

    "rpi-flashchroot-to-partclone")
        shift

        . ${DMGR_CURRENT_DIR}/functions_flash.sh

        _rpi_dir_to_partclone "$@"

        echo_notify "Rpi partclones image done at $2"
        ;;

    "rpi-flashpartclone-to-blk")
        shift

        . ${DMGR_CURRENT_DIR}/functions_flash.sh

        _rpi_partclone_to_blk "$@"

        echo_notify "Rpi flash done at $2"
        ;;

    "rpi-flashchroot-to-blk")
        shift

        . ${DMGR_CURRENT_DIR}/functions_flash.sh

        _rpi_dir_to_blk "$@"

        echo_notify "Rpi image done at $2"
        ;;

    "rpi-chroot-to-livedir")
        shift

        . ${DMGR_CURRENT_DIR}/functions_flash.sh

        _rpi_dir_to_livesys_dir "$@"

        echo_notify "Rpi live directory done at $2"
        ;;

    "help")
        echo "$DMGR_SYNOPSIS"
        exit 0
        ;;

    *)
        echo "$DMGR_SYNOPSIS"
        echo_die 1 "Unknown command $1"
        ;;
esac
