#!/bin/bash

error() {
	printf "%s\n" "$@" >&2
	exit 1
}

ROOTFS=$(ls --sort=time baseos-x2-*.tar* | head -n 1)
[[ -e  "$ROOTFS" ]] || error "rootfs not found"
ROOTFS_VERSION=${ROOTFS#baseos-x2-}
ROOTFS_VERSION=${ROOTFS_VERSION%.tar.*}

OUTPUT=baseos-x2-${ROOTFS_VERSION}

# cleanup version for test builds entries: remove trailing words
while [[ "$ROOTFS_VERSION" =~ -at.*-[a-z] ]]; do
	ROOTFS_VERSION=${ROOTFS_VERSION%-[a-z]*}
done


cat > "$OUTPUT.desc" <<EOF
swdesc_option PUBLIC
ATMARK_CERTS=certs/atmark-2.pem,certs/atmark-3.pem
swdesc_boot --board iot-g4-es1 imx-boot_armadillo_x2
swdesc_boot --board iot-g4-es2 imx-boot_armadillo_x2
swdesc_boot --board AGX4500 imx-boot_armadillo_x2
swdesc_tar "$ROOTFS" --preserve-attributes \
		     --version base_os "$ROOTFS_VERSION"
EOF

. ./tests/common.sh

build_check "$OUTPUT.desc" -- "version --board AGX4500 boot '20[^ ]* higher'" \
	"version base_os '[^ ]+ higher'" \
	"file .*imx-boot_armadillo_x2 '$ROOTFS'" \
	"file-tar scripts_extras.tar certs_atmark/atmark-2.pem certs_atmark/atmark-3.pem" \
	"swdesc imx-boot_armadillo_x2 '$ROOTFS' '# MKSWU_ALLOW_PUBLIC_CERT 1'"

mv "tests/out/$OUTPUT.swu" .
