#!/bin/bash

set -ex

cd "$(dirname "$0")"

. ./common.sh

build_check spaces "file test\ space.tar.zst"
build_check install_files \
	"file-tar ___tmp_swupdate_test*.tar.zst zoo/test\ space zoo/test\ space.tar"

cp -f ../mkimage.conf mkimage-aes.conf
echo 'ENCRYPT_KEYFILE="swupdate.aes-key"' >> mkimage-aes.conf
../genkey.sh --aes --config mkimage-aes.conf
conf=mkimage-aes.conf build_check aes

build_check board "swdesc 'iot-g4-es1 = '" \
	"version test '2 higher'" \
	"version --board iot-g4-es1 test '1 higher'"
build_check board_fail

build_check exec_quoting "swdesc 'touch /tmp/swupdate-test'"
build_check exec_readonly "swdesc 'podman run.*read-only.*touch.*/fail'"

build_fail ../examples/initial_setup
build_fail files_os_nonabs_fail
build_fail files_dotdot_fail

rm -f zoo/hardlink zoo/hardlink2
echo foo > zoo/hardlink
ln zoo/hardlink zoo/hardlink2
build_check hardlink_order
[ "$(cpio -t < out/hardlink_order.swu)" = "sw-description
sw-description.sig
scripts.tar.zst
hardlink
swupdate_post.sh.zst" ] || error "cpio content was not in expected order: $(cpio -t < out/hardlink_order.swu)"