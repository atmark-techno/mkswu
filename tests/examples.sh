#!/bin/bash

set -e

cd "$(dirname "$0")"

# build examples swu and check basic things (e.g. version included in sw-description)
. ./common.sh

# custom script: no prereq
build_check ../examples/custom_script.desc -- "file zst.scripts_pre.sh" \
	"swdesc custom_script_app.sh zst.scripts_pre.sh custom_script.app.sh 'POST_ACTION container'"

# sshd: build tar
build_check ../examples/enable_sshd.desc -- "version extra_os.sshd '[^ ]+ higher'" \
	"file-tar zst.enable_sshd*.tar ./.ssh/authorized_keys" \
	"swdesc ssh-keygen zst.enable_sshd.*tar rc-update"

# pull container: build tar
tar -C ../examples/nginx_start -cf ../examples/nginx_start.tar .
build_check ../examples/pull_container_nginx.desc -- \
	"file-tar zst.nginx_start*.tar ./etc/atmark/containers/nginx.conf" \
	"version pull_container_nginx '[^ ]+ higher'" \
	"version extra_os.pull_container_nginx '[^ ]+ higher'" \
	"swdesc zst.nginx_start.**tar docker.io/nginx"

# boot: bundle boot image
if ! [ -e ../imx-boot_armadillo_x2 ] \
    || [ "$(xxd -l 4 -p ../imx-boot_armadillo_x2)" != d1002041 ]; then
	{
		# create file with proper signature...
		echo '0: d1002041' | xxd -r
		# big enough to be compressed...
		dd if=/dev/zero bs=1M count=1 status=none
		# and with version recognizable
		echo '2020.04-at2-2-g16be576a6d2a-00001-ge7d8a230e98e'
	} > ../imx-boot_armadillo_x2
fi
build_check ../examples/boot.desc -- "file zst.imx-boot_armadillo_x2.*" "version boot '202.* higher'" "swdesc imx-boot_armadillo_x2"

# kernel plain: just a couple of files.. since we don't actually check installation create dummy ones
mkdir -p ../examples/kernel/lib/modules/5.10.82
touch ../examples/kernel/Image ../examples/kernel/armadillo_iotg_g4.dtb
touch ../examples/kernel/armadillo_iotg_g4-nousb.dtbo
build_check ../examples/kernel_update_plain.desc -- \
	"file-tar zst.*boot_Image*dtb*.tar Image armadillo_iotg_g4.dtb" \
	"swdesc update_preserve_files"

# encrypted linux
touch ../examples/Image.signed
build_check ../examples/encrypted_rootfs_linux_update.desc -- \
	"swdesc swupdate_bootdev"

# encrypted boot
if ! [ -e ../examples/imx-boot_armadillo_x2.enc ]; then
	ln -s ../imx-boot_armadillo_x2 ../examples/imx-boot_armadillo_x2.enc
fi
echo "123 version" > ../examples/armadillo_x2.dek_offsets
build_check ../examples/encrypted_imxboot_update.desc -- \
	"swdesc swupdate_bootdev" "swdesc 123 version"

# kernel apk: likewise we don't actually test install here,
touch ../examples/linux-at-5.10.9-r3.apk
build_check ../examples/kernel_update_apk.desc -- "swdesc linux-at-5.10.9-r3.apk"

# volume files: relative, absolute path
build_check ../examples/volumes_assets.desc -- \
	"file-tar zst.enable_sshd*tar ./root/.ssh/authorized_keys" \
	"file-tar zst.__assets_*tar volumes_assets.desc" \
	"swdesc /var/app/rollback/volumes/assets /var/app/volumes/data"

# no content but force version
build_check ../examples/container_clear.desc -- "swdesc CONTAINER_CLEAR"

# notify
build_check ../examples/enable_notify_led.desc -- \
	"swdesc 'MKSWU_NOTIFY_STARTING_CMD cd /sys'" \
	"swdesc 'MKSWU_NOTIFY_FAIL_CMD cd /sys'" \
	"swdesc 'MKSWU_NOTIFY_SUCCESS_CMD cd /sys'"
