#!/bin/bash

set -e

cd "$(dirname "$0")"

# build examples swu and check basic things (e.g. version included in sw-description)
. ./common.sh

# custom script: no prereq
build_check ../examples/custom_script.desc -- "file scripts_pre.sh.zst" \
	"swdesc custom_script_app.sh scripts_pre.sh.zst custom_script.app.sh 'POST_ACTION container' 'Built with mkswu [0-9]'"

# sshd: build tar
build_check ../examples/enable_sshd.desc -- "version extra_os.sshd '[^ ]+ higher'" \
	"file-tar enable_sshd*.tar.zst ./.ssh/authorized_keys" \
	"swdesc ssh-keygen enable_sshd.*tar.zst rc-update"

# pull container: build tar
tar -C ../examples/nginx_start -cf ../examples/nginx_start.tar .
build_check ../examples/pull_container_nginx.desc -- \
	"file-tar nginx_start*.tar.zst ./etc/atmark/containers/nginx.conf" \
	"version pull_container_nginx '[^ ]+ higher'" \
	"version extra_os.pull_container_nginx '[^ ]+ higher'" \
	"swdesc nginx_start.**tar.zst docker.io/nginx"

# boot: bundle boot image
[ -e ../imx-boot_armadillo_x2 ] \
	|| echo '2020.04-at2-2-g16be576a6d2a-00001-ge7d8a230e98e' > ../imx-boot_armadillo_x2
build_check ../examples/boot.desc -- "file imx-boot_armadillo_x2.*.zst" "version boot '202.* different'" "swdesc imx-boot_armadillo_x2"

# kernel plain: just a couple of files.. since we don't actually check installation create dummy ones
mkdir -p ../examples/kernel/lib/modules/5.10.82
touch ../examples/kernel/Image ../examples/kernel/armadillo_iotg_g4.dtb
touch ../examples/kernel/armadillo_iotg_g4-nousb.dtbo
build_check ../examples/kernel_update_plain.desc -- \
	"file-tar *boot_Image*dtb*.tar.zst Image armadillo_iotg_g4.dtb" \
	"swdesc update_preserve_files"

# kernel apk: likewise we don't actually test install here,
touch ../examples/linux-at-5.10.9-r3.apk
build_check ../examples/kernel_update_apk.desc -- "swdesc linux-at-5.10.9-r3.apk"

# volume files: relative, absolute path
build_check ../examples/volumes_assets.desc -- \
	"file-tar enable_sshd*tar.zst ./root/.ssh/authorized_keys" \
	"file-tar __assets_*tar.zst volumes_assets.desc" \
	"swdesc /var/app/rollback/volumes/assets /var/app/volumes/data"

# no content but force version
build_check ../examples/container_clear.desc -- "swdesc CONTAINER_CLEAR"

# notify
build_check ../examples/enable_notify_led.desc -- "swdesc MKSWU_NOTIFY_STARTING_CMD"
