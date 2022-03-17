#!/bin/bash

set -e

cd "$(dirname "$0")"

# build examples swu and check basic things (e.g. version included in sw-description)
. ./common.sh

# custom script: no prereq
build_check ../examples/custom_script "file custom_script_app.sh scripts.tar.zst" \
	"swdesc scripts.tar.zst custom_script.app.sh POSTACT_CONTAINER"

# sshd: build tar
build_check ../examples/enable_sshd "version extra_os.sshd '[^ ]+ higher'" \
	"file-tar enable_sshd*.tar.zst ./.ssh/authorized_keys" \
	"swdesc ssh-keygen enable_sshd.*tar.zst rc-update"

# pull container: build tar
tar -C ../examples/nginx_start -cf ../examples/nginx_start.tar .
build_check ../examples/pull_container_nginx \
	"file-tar nginx_start*.tar.zst ./etc/atmark/containers/nginx.conf" \
	"version pull_container_nginx '[^ ]+ higher'" \
	"version extra_os.pull_container_nginx '[^ ]+ higher'" \
	"swdesc nginx_start.**tar.zst docker.io/nginx"

# boot: prereq fullfilled by yakushima tar
[ -e ../imx-boot_armadillo_x2 ] \
	|| echo '2020.04-at2-2-g16be576a6d2a-00001-ge7d8a230e98e' > ../imx-boot_armadillo_x2
build_check ../examples/boot "file imx-boot_armadillo_x2.*.zst" "version boot '202.* different'" "swdesc imx-boot_armadillo_x2"

# kernel plain: just a couple of files.. since we don't actually check installation create dummy ones
touch ../examples/Image ../examples/imx8mp-yakushima-eva.dtb
mkdir -p ../examples/inst/lib/modules/5.10.82
build_check ../examples/kernel_update_plain \
	"file-tar *boot_Image*dtb*.tar.zst Image imx8mp-yakushima-eva.dtb" \
	"version extra_os.kernel '[^ ]+ different'" \
	"swdesc boot.*tar.zst"

# kernel apk: likewise we don't actually test install here,
touch ../examples/linux-at-5.10.9-r3.apk
build_check ../examples/kernel_update_apk "file linux-at-5.10.9-r3.apk" "swdesc linux-at-5.10.9-r3.apk"

# volume files: relative, absolute path
build_check ../examples/volumes_assets \
	"file-tar enable_sshd*tar.zst ./root/.ssh/authorized_keys" \
	"file-tar __assets_*tar.zst volumes_assets.desc" \
	"swdesc /var/app/rollback/volumes/assets /var/app/volumes/data"

# no content but force version
build_check ../examples/container_clear "swdesc CONTAINER_CLEAR"
