#!/bin/sh

set -e

if [ -n "$DEBUG_DMGR" -o -n "$DMGR_DEBUG" ]; then
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

  pc-chroot-flash       Flash a pc chroot to an raw image file
  pc-chroot-flash-live  Flash a pc chroot to a live system (block device
                        or file image)
  rpi-chroot-flash      Flash a rpi chroot to an raw image file
  rpi-chroot-flash-live Flash a rpi chroot to a live system (block device
                        or file image)
"

if [ $# -lt 1 ]; then
    echo "$DMGR_SYNOPSIS"
    echo_die 1 "Need arguments"
fi

DMGR_CMD_NAME=$1

. ${DMGR_CURRENT_DIR}/functions_chroot.sh
. ${DMGR_CURRENT_DIR}/functions_flash.sh

case $DMGR_CMD_NAME in
    "pc-debootstrap")
        shift
        _debootstrap_pc "$@"
        echo_notify "PC chroot generated at $DMGR_CHROOT_DIR"
        ;;

    "rpi-debootstrap")
        shift
        _debootstrap_rpi "$@"
        echo_notify "RPI chroot generated at $DMGR_CHROOT_DIR"
        ;;

    "chroot-exec")
        shift
        _chroot_exec "$@"
        echo_notify "Chroot executions done"
        ;;

    "chroot")
        shift
        _chroot "$@"
        ;;

    "pc-chroot-flash")
        shift
        _pc_chroot_flash "$@"
        ;;

    "pc-chroot-flash-live")
        shift
        _pc_chroot_flashlive "$@"
        ;;

    "rpi-chroot-flash")
        shift
        _rpi_chroot_flash "$@"
        ;;

    "rpi-chroot-flash-live")
        shift
        _rpi_chroot_flashlive "$@"
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
