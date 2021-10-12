#!/bin/bash

error() {
	echo "$@" >&2
	exit 1
}

[[ -r "swupdate.key" ]] || error "Cannot read swupdate.key"

ROOTFS=$(ls --sort=time alpine-aarch64-*.tar* | head -n 1)
[[ -e  "$ROOTFS" ]] || error "rootfs not found"
ROOTFS_VERSION=${ROOTFS#alpine-aarch64-}
ROOTFS_VERSION=${ROOTFS_VERSION%.tar.*}

OUTPUT=armadillo-x2-${ROOTFS_VERSION}

cat > "$OUTPUT.desc" <<EOF
DEBUG_SWDESC="# ALLOW_PUBLIC_CERT ALLOW_EMPTY_LOGIN"
swdesc_uboot --board iot-g4-g4-eva imx-boot_yakushima-eva
swdesc_uboot --board iot-g4-es1 imx-boot_yakushima-es1
swdesc_uboot --board iot-g4-es2 imx-boot_yakushima-es1
swdesc_tar "$ROOTFS" --version base_os "$ROOTFS_VERSION"
EOF

. ./tests/common.sh

build_check "$OUTPUT" "version uboot 20.*" "version base_os .+" \
	"file imx-boot_yakushima-eva.* imx-boot_yakushima-es1.* '$ROOTFS'" \
	"swdesc imx-boot_yakushima-eva imx-boot_yakushima-es1 '$ROOTFS'"
mv "tests/out/$OUTPUT.swu" .
