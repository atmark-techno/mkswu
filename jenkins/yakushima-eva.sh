#!/bin/bash

error() {
	echo "$@" >&2
	exit 1
}

[[ -r "swupdate.key" ]] || error "Cannot read swupdate.key"

for ROOTFS in alpine-aarch64-*.tar.gz; do
	[[ -e  "$ROOTFS" ]] || error "rootfs not found"
	break
done
[[ -e  "$ROOTFS" ]] || error "rootfs not found (should never see this)"
ROOTFS_VERSION=${ROOTFS#alpine-aarch64-}
ROOTFS_VERSION=${ROOTFS_VERSION%%-*}

cat >> yakushima-eva.conf <<EOF
PRIVKEY=swupdate.key
PUBKEY=swupdate.pem
UBOOT=imx-boot_yakushima-eva
BASE_OS="$ROOTFS"
BASE_OS_VERSION="${ROOTFS_VERSION}"
EOF

./mkimage.sh -c yakushima-eva.conf -o yakushima-eva.swu

