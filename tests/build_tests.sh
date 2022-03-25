#!/bin/bash

set -ex

cd "$(dirname "$0")"

. ./common.sh

build_check spaces "file test\ space.tar.zst"
build_check install_files \
	"file-tar ___tmp_swupdate_test*.tar.zst zoo/test\ space zoo/test\ space.tar"

echo 'ENCRYPT_KEYFILE="swupdate.aes-key"' >> mkswu-aes.conf
"$MKSWU" --genkey --aes --config mkswu-aes.conf
MKSWU_ENCRYPT_KEYFILE=$PWD/swupdate.aes-key build_check aes \
	"swdesc 'ivt ='" "file scripts.tar.zst.enc"

build_check board "swdesc 'iot-g4-es1 = '" \
	"version test '2 higher'" \
	"version --board iot-g4-es1 test '1 higher'"
build_check board_fail

build_check exec_quoting "swdesc 'touch /tmp/swupdate-test'"
build_check exec_readonly "swdesc 'podman run.*read-only.*touch.*/fail'"

build_check swdesc_script
build_check swdesc_script_nochroot

build_fail ../examples/initial_setup
build_fail files_os_nonabs_fail
build_fail files_dotdot_fail
build_fail version_toobig_fail
build_fail version_toobig2_fail
build_fail version_alnum_fail
build_fail version_alnum2_fail
build_fail version_non_alnum_fail
build_fail version_component_space_fail
build_fail version_space_fail
build_fail version_different_plus_fail
build_fail version_different_long_fail

rm -f zoo/hardlink zoo/hardlink2
echo foo > zoo/hardlink
ln zoo/hardlink zoo/hardlink2
build_check hardlink_order
[ "$(cpio --quiet -t < out/hardlink_order.swu)" = "sw-description
sw-description.sig
scripts.tar.zst
hardlink
swupdate_post.sh.zst" ] || error "cpio content was not in expected order: $(cpio --quiet -t < out/hardlink_order.swu)"

rm -rf "$TESTS_DIR/out/init"
"$MKSWU" --config-dir "$TESTS_DIR/out/init" --init <<EOF \
	|| error "mkswu --init failed"
cn
privkeypass
privkeypass


root
root
atmark
atmark
y

EOF
# in order:
# certif common name, private key pass x2, aes encryption (default=n), allow atmark updates (default=y),
# root pass x2, atmark pass x2, autoupdate (force y) + frequency (default weekly)

dir="$TESTS_DIR/out/init/.initial_setup" check swdesc usermod
dir="$TESTS_DIR/out/init/.initial_setup" check swdesc swupdate-url
