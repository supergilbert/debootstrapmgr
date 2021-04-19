# DEBOOTSTRAPMGR

## /!\ Caution use this software at your own risk

* This software run under root privilegies
  * It can erase all your device data
    * It may not be fully tested

debootstrapmgr is licensed under the MIT License, see [LICENSE.txt](https://github.com/ocornut/imgui/blob/master/LICENSE.txt) for more information.

(This software is used to facilitate the creation of bootable Debian system)

## Debian dependencies

Run on amd64 architecture.

### Package needed

binfmt-support coreutils debootstrap dosfstools e2fsprogs kpartx parted qemu-system-arm qemu-user-static

### Package suggested

qemu-system-x86

## DEBOOTSTRAPMGR SYNOPSIS

    usage: debootstrapmgr.sh <command> [<args>]

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
      mklive-squashfs Generate a live squashfs file

    Flash commands (/!\ caution in what you are flashing)

      pc-chroot-flash       Flash a pc chroot to an raw image file
      pc-chroot-flash-live  Flash a pc chroot to a live system (block device
                            or file image)
      rpi-chroot-flash      Flash a rpi chroot to an raw image file
      rpi-chroot-flash-live Flash a rpi chroot to a live system (block device
                            or file image)
      dump-default-pc-json
      dump-default-rpi-json
      dump-default-live-json

## TODO

A flash tool that generate fstab partition and bootload from a file format and chroot directory.
