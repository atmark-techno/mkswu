#!/bin/bash

error() {
	echo "$@" >&2
	exit 1
}

[[ -r "swupdate.key" ]] || error "Cannot read swupdate.key"

ROOTFS=$(ls --sort=time alpine-aarch64-*.tar.gz | head -n 1)
[[ -e  "$ROOTFS" ]] || error "rootfs not found"
ROOTFS_VERSION=${ROOTFS#alpine-aarch64-}
ROOTFS_VERSION=${ROOTFS_VERSION%.tar.*}
# if multiple dashes only keep until first one
ROOTFS_VERSION=${ROOTFS_VERSION%%-*}

cat > yakushima-eva.conf <<EOF
PRIVKEY=swupdate.key
PUBKEY=swupdate.pem
UBOOT=imx-boot_yakushima-eva
BASE_OS="$ROOTFS"
BASE_OS_VERSION="${ROOTFS_VERSION}"
EOF

./mkimage.sh -c yakushima-eva.conf -o yakushima-eva.swu
