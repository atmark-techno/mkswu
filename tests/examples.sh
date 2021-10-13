#!/bin/bash

set -e

# build examples swu and check basic things (e.g. version included in sw-description)
. ./tests/common.sh

# custom script: no prereq
build_check examples/custom_script "file custom_script_app.sh scripts.tar.zst" \
	"swdesc scripts.tar.zst custom_script.app.sh NO_REBOOT_ALLOW"

# sshd: build tar
build_check examples/enable_sshd "version extra_os.sshd .+" \
	"file-tar examples_enable_sshd_root__root___433ab7755d241729f0e12b13e67effc22b8e667b.tar.zst ./.ssh/authorized_keys" \
	"swdesc ssh-keygen enable_sshd.*tar.zst rc-update"

# pull container: build tar
tar -C examples/nginx_start -cf examples/nginx_start.tar .
build_check examples/pull_container_nginx \
	"file-tar examples_nginx_start____25c7d7c1622cc37a871fd62c82d6dda8414a86c3.tar.zst ./etc/atmark/containers/nginx.conf" \
	"swdesc nginx_start.**tar.zst docker.io/nginx"

# uboot: prereq fullfilled by yakushima tar
build_check examples/uboot "file imx-boot_yakushima-.*.zst" "version uboot 202.*" "swdesc imx-boot_yakushima-"

# kernel plain: just a couple of files.. since we don't actually check installation create dummy ones
touch examples/Image examples/imx8mp-yakushima-eva.dtb
build_check examples/kernel_update_plain \
	"file-tar examples__boot_Image..mp_yakushima_eva_dtb_2c726bdd401d2c4936f81d30172a8c81562ece87.tar.zst Image imx8mp-yakushima-eva.dtb" \
	"swdesc boot.*tar.zst"

# kernel apk: likewise we don't actually test install here,
touch examples/linux-at-5.10.9-r3.apk
build_check examples/kernel_update_apk "file linux-at-5.10.9-r3.apk" "swdesc linux-at-5.10.9-r3.apk"
