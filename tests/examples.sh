#!/bin/bash

set -e

cd "$(dirname "$0")"

# build examples swu and check basic things (e.g. version included in sw-description)
. ./common.sh

# custom script: no prereq
build_check ../examples/custom_script "file custom_script_app.sh scripts.tar.zst" \
	"swdesc scripts.tar.zst custom_script.app.sh POSTACT_CONTAINER"

# sshd: build tar
build_check ../examples/enable_sshd "version extra_os.sshd .+" \
	"file-tar enable_sshd*.tar.zst ./.ssh/authorized_keys" \
	"swdesc ssh-keygen enable_sshd.*tar.zst rc-update"

# pull container: build tar
tar -C ../examples/nginx_start -cf ../examples/nginx_start.tar .
build_check ../examples/pull_container_nginx \
	"file-tar nginx_start*.tar.zst ./etc/atmark/containers/nginx.conf" \
	"swdesc nginx_start.**tar.zst docker.io/nginx"

# boot: prereq fullfilled by yakushima tar
touch ../imx-boot_armadillo_x2
build_check ../examples/boot "file imx-boot_armadillo_x2.*.zst" "version boot 202.*" "swdesc imx-boot_armadillo_x2"

# kernel plain: just a couple of files.. since we don't actually check installation create dummy ones
touch ../examples/Image ../examples/imx8mp-yakushima-eva.dtb
build_check ../examples/kernel_update_plain \
	"file-tar *boot_Image*dtb*.tar.zst Image imx8mp-yakushima-eva.dtb" \
	"swdesc boot.*tar.zst"

# kernel apk: likewise we don't actually test install here,
touch ../examples/linux-at-5.10.9-r3.apk
build_check ../examples/kernel_update_apk "file linux-at-5.10.9-r3.apk" "swdesc linux-at-5.10.9-r3.apk"
