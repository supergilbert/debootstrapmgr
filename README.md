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

binfmt-support coreutils debootstrap dosfstools e2fsprogs kpartx partclone parted qemu-system-arm qemu-user-static

### Package suggested

qemu-system-x86

## DEBOOTSTRAPMGR SYNOPSIS

    usage: debootstrapmgr <command> [<args>]

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
       Searching for a way to bind debian bootload mechanism partition table and ...
       fstab)

      pc-flashchroot-to-img        Flash a pc chroot to an raw image file
      rpi-flashchroot-to-blk       Flash a rpi chroot to an raw image file
      rpi-flashchroot-to-partclone Flash a rpi chroot to partclones tgz image
      rpi-flashpartclone-to-blk    Flash a partclones tgz image to a block device
      rpi-chroot-to-livedir        Generate filesquash live system directory from
                                   chroot

## TODO

A flash tool that generate fstab partition and bootload from a file format and chroot directory.
