#!/bin/bash

set -e

# build examples swu and check basic things (e.g. version included in sw-description)
. ./tests/common.sh

# custom script: no prereq
build_check examples/custom_script "file custom_script_app.sh"

# sshd: build tar
tar -C examples/enable_sshd -cf examples/enable_sshd.tar .
build_check examples/enable_sshd "version extra_os .+" "file enable_sshd_genkeys.sh" "file-tar enable_sshd.tar.zst ./etc/runlevels/default/sshd ./root/.ssh/authorized_keys"

# pull container: build tar
tar -C examples/nginx_start -cf examples/nginx_start.tar .
build_check examples/pull_container_nginx "file-tar nginx_start.tar.zst ./etc/atmark/containers/nginx.conf" "file container_docker_io_nginx_alpine.pull"

# uboot: prereq fullfilled by yakushima tar
build_check examples/uboot "file imx-boot_yakushima-eva.zst" "version uboot 202.*"

# kernel plain: just a couple of files.. since we don't actually check installation create dummy ones
touch examples/Image examples/imx8mp-yakushima-eva.dtb
build_check examples/kernel_update_plain "file-tar boot.tar.zst Image imx8mp-yakushima-eva.dtb"

# kernel apk: likewise we don't actually test install here,
touch examples/linux-at-5.10.9-r3.apk
build_check examples/kernel_update_apk "file linux-at-5.10.9-r3.apk"
