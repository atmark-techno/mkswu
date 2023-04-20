#!/bin/bash

set -e

cd "$(dirname "$0")"

. ./common.sh

build_check spaces.desc -- "file test\ space.tar.zst" \
	"file .*test_space_tar.*target_load.*\.zst" \
	"swdesc 'path = \"/tmp/test space\"'"
name="--odd desc" build_check --- --odd\ desc.desc
# --- is made into -- for mkswu
[ "$(grep -c 'filename = "zoo' "out/.--odd desc/sw-description")" = 1 ] \
	|| error "zoo archive was not included exactly once"
build_check install_files.desc -- \
	"file-tar ___tmp_swupdate_test*.tar.zst zoo/test\ space zoo/test\ space.tar" \
	"swdesc '# MKSWU_FORCE_VERSION 1'"

[ -e out/mkswu-aes.conf ] || touch out/mkswu-aes.conf
"$MKSWU" --genkey --cn test --plain --config out/mkswu-aes.conf --noprompt \
	|| error "mkswu --genkey failed"
[ "$(head -n 1 out/swupdate.pem)" = "# swupdate.pem: test" ] \
	|| error "swupdate.pem header was not correct"
(
	# run in subshell to unexport MKSWU_ENCRYPT_KEYFILE from common.sh
	unset MKSWU_ENCRYPT_KEYFILE
	"$MKSWU" --genkey --aes --config out/mkswu-aes.conf --noprompt \
		|| error "mkswu --genkey --aes failed"

	build_check aes.desc --config out/mkswu-aes.conf -- \
		"swdesc 'ivt ='" "file scripts_pre.sh.zst.enc"
) || exit
MKSWU_ENCRYPT_KEYFILE=$PWD/out/swupdate.aes-key build_check aes.desc -- \
	"swdesc 'ivt ='" "file scripts_pre.sh.zst.enc"

# test old variables backwards compatibility
printf "%s\n" "component=test" "install_if=different" "version=1" "swdesc_files build_tests.sh" \
    | name=compat_version_vars build_check - -- \
        "swdesc 'VERSION test 1 different'"

build_check board.desc -- "swdesc 'iot-g4-es1 = '" \
	"version test '2 higher'" \
	"version --board iot-g4-es1 test '1 higher'"
build_check board_fail.desc --

build_check exec_quoting.desc -- "swdesc 'touch /tmp/swupdate-test'"
build_check exec_readonly.desc -- "swdesc 'podman run.*read-only.*touch.*/fail'"

name=exec_quoting_readonly build_check exec_quoting.desc exec_readonly.desc -- \
	"swdesc 'touch /tmp/swupdate-test'" \
	"swdesc 'podman run.*read-only.*touch.*/fail'"

printf "%s\n" "swdesc_files build_tests.sh --version stdin 1" \
	| name=stdin build_check - -- "swdesc 'build_tests.sh'" \

printf "%s\n" "swdesc_files build_tests.sh --version stdin 1" \
	| name=stdin_quoting build_check exec_quoting.desc - -- \
		"swdesc 'touch /tmp/swupdate-test'" \
		"swdesc 'build_tests.sh'" \

build_check swdesc_script.desc --
build_check swdesc_script_nochroot.desc --

build_check two_scripts.desc -- \
	"swdesc 'one' 'two'"

build_check update_certs_atmark.desc -- \
	"file-tar scripts_extras.tar certs_atmark/atmark-1.pem certs_atmark/atmark-2.pem"

build_check update_certs_user.desc -- \
	"file-tar scripts_extras.tar certs_user/swupdate*.pem certs_user/atmark-1.pem"
build_check update_certs_user.desc -- \
	"file-tar scripts_extras.tar certs_user/swupdate*.pem"

build_fail ../examples/initial_setup.desc
build_fail files_os_nonabs_fail.desc
build_fail files_dotdot_fail.desc

version_fail() {
	printf "%s\n" "swdesc_command --version ${*@Q} 'echo ok'" \
		| name=version build_fail -
}
version_fail test abc # base version must be num
version_fail test 1.2-123abc # mixed alnum
version_fail 'test space' 1 # space in component
version_fail test '1 2' # space in version
version_fail test 1.2.3.4-test --install-if different # only up to 3 digits with -
version_fail test 1.2.3+test --install-if different # + ignored if no -
version_fail test 1.2-@bc # non alnum
version_fail test 1.2.3.12345678 # too big for 4 digits
version_fail test 1234567890123 # too big

rm -f zoo/hardlink zoo/hardlink2
echo foo > zoo/hardlink
ln zoo/hardlink zoo/hardlink2
build_check hardlink_order.desc --
[ "$(cpio --quiet -t < out/hardlink_order.swu)" = "sw-description
sw-description.sig
scripts_pre.sh.zst
hardlink
scripts_post.sh.zst" ] || error "cpio content was not in expected order: $(cpio --quiet -t < out/hardlink_order.swu)"

rm -rf "$TESTS_DIR/out/init" "$TESTS_DIR/out/init_noupdate" "$TESTS_DIR/out/init_noatmark"
"$MKSWU" --config-dir "$TESTS_DIR/out/init" --init <<EOF \
	|| error "mkswu --init failed"
cn
privkeypass
privkeypass


somepass
differentpass(ask again)
root
root
atmark
atmark
y

EOF
"$MKSWU" --config-dir "$TESTS_DIR/out/init_noupdate" --init <<EOF \
	|| error "mkswu --init noupdate failed"

cn(empty=should reask)
somepass
differentpass(ask again)




root
root
somepass
differentpass(ask again)



EOF
"$MKSWU" --config-dir "$TESTS_DIR/out/init_noatmark" --init <<EOF \
	|| error "mkswu --init noatmark failed"
cn
keypass
keypass
y
n

root
root


EOF
# in order:
# certif common name, private key pass x2, aes encryption (default=n), allow atmark updates (default=y),
# root pass x2, atmark pass x2, autoupdate (force y) + frequency (default weekly)
# frequency skipped if autoupdate = n (default)

grep -q swupdate-url "$TESTS_DIR/out/init/initial_setup.desc" \
	|| error "autoupdate not enabled"
grep -q swupdate-url "$TESTS_DIR/out/init_noupdate/initial_setup.desc" \
	&& error "autoupdate incorrectly enabled (noupdate)"
grep -q swupdate-url "$TESTS_DIR/out/init_noatmark/initial_setup.desc" \
	&& error "autoupdate incorrectly enabled (noatmark)"
grep -qxF "swdesc_command '> /etc/swupdate.pem'" \
		"$TESTS_DIR/out/init_noatmark/initial_setup.desc" \
	|| error "noatmark kept atmark certs"
grep -qxF "swdesc_command '> /etc/swupdate.pem'" \
		"$TESTS_DIR/out/init/initial_setup.desc" \
	&& error "incorrectly wiped atmark certs"

# validate generated passwords match
checkpass() {
	local dir="$1"
	local user="$2"
	local pass="$3"
	local desc
	local check

	if [ -z "$pass" ]; then
		grep -qE "^[^#]*\"usermod -L $user\"" "$TESTS_DIR/out/$dir/initial_setup.desc" \
			|| error "$user not locked in $dir"
		return
	fi

	desc=$(sed -ne "s/^[^#]*'\"'\(.*\)'\"'.*$user.*/\1/p" "$TESTS_DIR/out/$dir/initial_setup.desc")
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
	[ "$desc" = "$check" ] || error "Error: $pass was invalid (got $desc expected $check for $dir)"
}
checkpass init atmark atmark
checkpass init root root
checkpass init_noupdate atmark
checkpass init_noupdate root root

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

# check version update
DESC="$TESTS_DIR/out/version_update.desc"
echo 'swdesc_option component=foo version=1' > "$DESC"
"$MKSWU" --update-version "$DESC"
grep -q version=2 "$DESC" || error "version was not updated to 2"
grep -qx "swdesc_option component=foo version=2" "$DESC" \
	|| error "non-version part was cobblered"
"$MKSWU" --update-version "$DESC" --version-base=5.10
grep -q version=5.10-0 "$DESC" || error "version was not updated to 5.10-0"
"$MKSWU" --update-version "$DESC" --version-base=5.10
grep -q version=5.10-1 "$DESC" || error "version was not updated to 5.10-1"
echo 'swdesc_option version=5.10 component=foo' > "$DESC"
"$MKSWU" --update-version "$DESC"
grep -q version=5.11 "$DESC" || error "version was not updated to 5.11"
grep -qx "swdesc_option version=5.11 component=foo" "$DESC" \
	|| error "non-version part was cobblered"
"$MKSWU" --update-version "$DESC" --version-base=5.10 \
	&& error "should refuse to update 5.11 to 5.10-0"

# test is ok even if last command failed...
true
