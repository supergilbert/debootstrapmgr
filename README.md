# DEBIAN-GENERATOR

## /!\ Caution use this software at your own risk

* This software run under root privilegies
  * It can erase all your device data
    * It may not be fully tested

debian-generator is licensed under the MIT License, see [LICENSE.txt](https://github.com/supergilbert/debian-generator/blob/master/LICENSE.txt) for more information.

(This software is used to facilitate the creation of bootable Debian system)

## Debian dependencies

Run on amd64 architecture.

### Package needed

binfmt-support coreutils debootstrap dosfstools e2fsprogs kpartx parted qemu-system-arm qemu-user-static

### Package suggested

qemu-system-x86

## DEBGEN SYNOPSIS

    usage: debgen <command> [<args>]

    A tool to flash, generate or prepare debian chroot for RPI and PC architecture.

    Commands:

      help  Display this help

    Chroot commands

      pc-chroot       Use debootstrap to generate a default pc chroot
      rpi-chroot      Use debootstrap to generate a default rpi chroot
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
      pc-flash-iso
      rpi-flash
      rpi-flash-live
