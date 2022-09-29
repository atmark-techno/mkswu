#!/bin/bash

set -ex

cd "$(dirname "$0")"

. ./common.sh

build_check spaces "file test\ space.tar.zst"
build_check install_files \
	"file-tar ___tmp_swupdate_test*.tar.zst zoo/test\ space zoo/test\ space.tar" \
	"swdesc '# MKSWU_FORCE_VERSION 1'"

echo 'ENCRYPT_KEYFILE="swupdate.aes-key"' >> mkswu-aes.conf
"$MKSWU" --genkey --aes --config mkswu-aes.conf --noprompt
MKSWU_ENCRYPT_KEYFILE=$PWD/swupdate.aes-key build_check aes \
	"swdesc 'ivt ='" "file scripts_pre.sh.zst.enc"

build_check board "swdesc 'iot-g4-es1 = '" \
	"version test '2 higher'" \
	"version --board iot-g4-es1 test '1 higher'"
build_check board_fail

build_check exec_quoting "swdesc 'touch /tmp/swupdate-test'"
build_check exec_readonly "swdesc 'podman run.*read-only.*touch.*/fail'"

build_check swdesc_script
build_check swdesc_script_nochroot

build_check update_certs_atmark \
	"file-tar scripts_extras.tar certs_atmark/atmark-1.pem certs_atmark/atmark-2.pem"

build_check update_certs_user \
	"file-tar scripts_extras.tar certs_user/swupdate*.pem certs_user/atmark-1.pem"
build_check update_certs_user \
	"file-tar scripts_extras.tar certs_user/swupdate*.pem"

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
scripts_pre.sh.zst
hardlink
scripts_post.sh.zst" ] || error "cpio content was not in expected order: $(cpio --quiet -t < out/hardlink_order.swu)"

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

# validate generated passwords match
checkpass() {
	local user="$1"
	local pass="$2"
	local desc
	local check
	desc=$(sed -ne "s/^[ \t].*'\"'\(.*\)'\"'.*$user.*/\1/p" "$TESTS_DIR/out/init/initial_setup.desc")
	if command -v python3 >/dev/null; then
		check=$(python3 -c "import crypt; print(crypt.crypt('$pass', '$desc'))") \
			|| error "python3 crypt call failed"
	elif command -v mkpasswd > /dev/null; then
		check="${desc#\$*\$}"
		check="${check%%\$*\$}"
		check=$(mkpasswd "$pass" "$check") \
			|| error "mkpasswd call failed"
	else
		error "install either python3 or mkpasswd"
	fi
	[ "$desc" = "$check" ] || error "Error: $pass was invalid (got $desc expected $check)"
}
checkpass atmark atmark
checkpass root root

# test atmark pass is regenerated on old version
sed -i -e 's/version=[0-9]/version=1/' "$TESTS_DIR/out/init/initial_setup.desc"
"$MKSWU" --config-dir "$TESTS_DIR/out/init" --init <<EOF \
	|| error "mkswu --init on old version failed"


EOF
# atmark pass and confirm; empty = lock
grep -q "usermod -L atmark" "$TESTS_DIR/out/init/initial_setup.desc" \
	|| error "atmark account not locked after second init"


dir="$TESTS_DIR/out/init/.initial_setup" check swdesc usermod
dir="$TESTS_DIR/out/init/.initial_setup" check swdesc swupdate-url

rm -rf "$TESTS_DIR/out/genkey"
"$MKSWU" --config-dir "$TESTS_DIR/out/genkey" --genkey --cn test --plain
echo y | "$MKSWU" --config-dir "$TESTS_DIR/out/genkey" --genkey --cn test --plain
(
	CONFIG_DIR="$TESTS_DIR/out/genkey"
	. ../mkswu.conf.defaults
	. "$CONFIG_DIR/mkswu.conf"
	[ "$UPDATE_CERTS" = yes ] || error "bad UPDATE_CERTS: $UPDATE_CERTS"
	[ "$PUBKEY" = "$TESTS_DIR/out/genkey/swupdate.pem,$TESTS_DIR/out/genkey/swupdate-2.pem" ] || error "bad PUBKEY: $PUBKEY"
	[ "$NEW_PRIVKEY" = "$TESTS_DIR/out/genkey/swupdate-2.key" ] || error "bad PRIVKEY: $PRIVKEY"
) || error "genkey test failed"
