#!/bin/sh -e

CURRENT_DIR=$(dirname $0)

SYNOPSIS="\
Usage: make_deb.sh <command>
  build     Build an unsigned debian package
  debian    Generate a debian directory
  debian-no-qemu-version-dep
            Generate a debian directory (without qemu debian version dependency
  help      Display this help
"

if [ $# -ne 1 ]; then
    echo "$SYNOPSIS"
    echo "Need one argument"
    exit 1
fi

case "$1" in
    "help")
        echo "$SYNOPSIS"
        ;;

    "debian")
        set -x
        if [ -d ${CURRENT_DIR}/debian ]; then
            rm -rf ${CURRENT_DIR}/debian
        fi
        cp -R ${CURRENT_DIR}/src/debian_tmp ${CURRENT_DIR}/debian
        cp ${CURRENT_DIR}/debian/debian_control ${CURRENT_DIR}/debian/control
        ;;

    "debian-no-qemu-version-dep")
        set -x
        if [ -d ${CURRENT_DIR}/debian ]; then
            rm -rf ${CURRENT_DIR}/debian
        fi
        cp -R ${CURRENT_DIR}/src/debian_tmp ${CURRENT_DIR}/debian
        cp ${CURRENT_DIR}/src/debian_tmp/no_qemu_version_control_dep ${CURRENT_DIR}/debian/control
        ;;

    "build")
        set -x
        if [ ! -d ${CURRENT_DIR}/debian ]; then
            echo "Building debian directory"
            $0 debian
        else
            echo "debian directory found"
        fi
        cd $CURRENT_DIR
        debuild -b -us -uc
        cd -
        ;;

    *)
        echo "$SYNOPSIS"
        echo "Unknown command $1"
        exit 1
esac
