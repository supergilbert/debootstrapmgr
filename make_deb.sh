#!/bin/sh -e

CURRENT_DIR=$(dirname $0)

SYNOPSIS="\
Usage: make_deb.sh <command>
  debian                 Generate a debian directory
  debian_no_qemu_version Generate a debian directory (without qemu debian
                         version dependency
  debuild                Build an unsigned debian package
  help                   Display this help
"

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
    "debian_no_qemu_version")
        set -x
        if [ -d ${CURRENT_DIR}/debian ]; then
            rm -rf ${CURRENT_DIR}/debian
        fi
        cp -R ${CURRENT_DIR}/src/debian_tmp ${CURRENT_DIR}/debian
        cp ${CURRENT_DIR}/src/debian_tmp/no_qemu_version_control ${CURRENT_DIR}/debian/control
        ;;
    "debuild")
        set -x
        if [ ! -d ${CURRENT_DIR}/debian ]; then
            $0 debian
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
