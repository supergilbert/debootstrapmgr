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
  mklive-squashfs Generate a live system squashfs file

Dump commands
 Output default json disk architecture

  dump-default-pc-json
  dump-default-rpi-json
  dump-default-live-json

Flash commands (/!\ caution in what you are flashing)
  All flash command can be done on a block device or file a image

  pc-flash
  pc-flash-live
  rpi-flash
  rpi-flash-live
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
        echo_notify "Chroot generated"
        ;;

    "rpi-debootstrap")
        shift
        _debootstrap_rpi "$@"
        echo_notify "Chroot generated"
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

    "mklive-squashfs")
        shift
        _chroot_to_live_squashfs "$@"
        echo_notify "Live file squashfs executions done"
        ;;

    "pc-flash")
        shift
        _flash_pc "$@"
        echo_notify "Flash done"
        ;;

    "pc-flash-live")
        shift
        _flash_pc_live "$@"
        echo_notify "Flash done"
        ;;

    "rpi-flash")
        shift
        _flash_rpi "$@"
        echo_notify "Flash done"
        ;;

    "rpi-flash-live")
        shift
        _flash_rpi_live "$@"
        echo_notify "Flash done"
        ;;

    "help")
        echo "$DMGR_SYNOPSIS"
        exit 0
        ;;

    "dump-default-pc-json")
        echo "$DEFAULT_FSTAB_JSON"
        exit 0
        ;;

    "dump-default-rpi-json")
        echo "$DEFAULT_FSTAB_RPI_JSON"
        exit 0
        ;;

    "dump-default-live-json")
        echo "$DEFAULT_LIVE_JSON"
        exit 0
        ;;

    *)
        echo "$DMGR_SYNOPSIS"
        echo_die 1 "Unknown command $1"
        ;;
esac
