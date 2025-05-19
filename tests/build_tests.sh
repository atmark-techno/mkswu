#!/bin/bash

set -ex

cd "$(dirname "$0")"

. ./common.sh

# prepare file used by tests here.
mkdir -p out/zoo
echo "test content" > out/zoo/test\ space
echo "test content" > out/zoo/test\ space2
tar -C out/zoo -cf out/zoo/test\ space.tar test\ space
echo foo > out/zoo/hardlink
ln -f out/zoo/hardlink out/zoo/hardlink2
{ echo foo; dd if=/dev/zero bs=1M count=1; echo bar; } > out/semibig

build_check spaces.desc -- "file zst.test\ space.tar" \
	"file zst\..*out_zoo_test_space_t.*arget_load.*" \
	"swdesc 'path = \"/tmp/test space\"'"
name="--odd desc" build_check --- --odd\ desc.desc
# --- is made into -- for mkswu
[ "$(grep -c 'filename = "zst.out_zoo' "out/.--odd desc/sw-description")" = 1 ] \
	|| error "zoo archive was not included exactly once"
build_check install_files.desc -- \
	"file-tar zst.out__tmp_swupdate_te*.tar zoo/test\ space zoo/test\ space.tar" \
	"swdesc '# MKSWU_FORCE_VERSION 1'"

# full file hash then 3 chunks
build_check semibig.desc -- \
	"swdesc 877d0aeaf78643fac45476f7a34f5ac3e1013e67c347df2a0eafc42b90666246 \
		5dca1b3c3ddd35bf8976ad0fd64481a0e425acd69a6567013453763f42f05743 \
		07854d2fef297a06ba81685e660c332de36d5d18d546927d30daad6d7fda1541 \
		38e8b9f6e593b8012f9b22c46258b0a8b3c539d70e30732fdd466dfc11752d12 \
		chunked_sha256 'sha256 =' 'size ='"

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
		"swdesc 'ivt ='" "file enc.zst.scripts_pre.sh"
) || exit
MKSWU_ENCRYPT_KEYFILE=$PWD/out/swupdate.aes-key build_check aes.desc -- \
	"swdesc 'ivt ='" "file enc.zst.scripts_pre.sh"

build_check make_sbom.desc -- "sbom 'pkg:oci/mirror.gcr.io%2Falpine' 'test\ space' 'test\ space.tar'"

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
	| name=stdin build_check - -- \
		"swdesc 'build_tests.sh'" \
		"swdesc_absent 'tar has /var/app/volumes'"

printf "%s\n" "swdesc_files build_tests.sh --version stdin 1" \
	| name=stdin_quoting build_check exec_quoting.desc - -- \
		"swdesc 'touch /tmp/swupdate-test'" \
		"swdesc 'build_tests.sh'" \

name=files_app_volumes build_check  - -- \
	"swdesc_count 2 'tar has /var/app/volumes'" <<'EOF'
mkdir -p "$OUTDIR/dir/var/app/volumes"
swdesc_option version=1
# no match
swdesc_files "$OUTDIR/dir"
# match
swdesc_files --extra-os "$OUTDIR/dir"
# also match
swdesc_files --extra-os --dest /var "$OUTDIR/dir/var"
EOF

build_check swdesc_script.desc -- \
	'swdesc_absent "script has /var/app/volumes"'
build_check swdesc_script_nochroot.desc --

build_check script_volumes.desc -- \
	'swdesc "script has /var/app/volumes"'

build_check two_scripts.desc -- \
	"swdesc 'one' 'two'"

# replace ' with regular expression dots since they cannot be escaped
build_check stdout_info.desc -- \
	"swdesc 'sh -c .\{ echo message to info; }. >&\\\$\{SWUPDATE_INFO_FD:-1\} --' \
		'sh -c .\{ echo message to debug; }. --'"

echo 'swdesc_embed_container doesnotexist' \
	| name="container_enoent_fail" build_fail -
echo 'swdesc_embed_container build_tests.sh' \
	| name="container_nottar_warn" build_check - 2>&1 \
	| grep -q "was not in docker-archive format" \
	|| error "mkswu did not warn for container not a tar"
if command -v podman && command -v jq > /dev/null; then
	id=$(podman image list --format='{{.Id}}' --sort=size | head -n 1)
	if [ -z "$id" ]; then
		id=$(echo 'FROM scratch' | podman build -t empty - -q || true)
	fi
	# ignore any error if podman cannot build in test environment
	if [ -n "$id" ]; then
		rm -f out/container.tar
		podman save -o out/container.tar "$id"
		echo 'swdesc_embed_container out/container.tar' \
			| name="container_notag_warn" build_check - 2>&1 \
			| grep -q "did not contain any tag" \
			|| error "mkswu did not warn for no tag in container"
	fi
fi

build_check update_certs_atmark.desc -- \
	"file-tar scripts_extras.tar certs_atmark/atmark-2.pem certs_atmark/atmark-3.pem"

build_check update_certs_user.desc -- \
	"file-tar scripts_extras.tar certs_user/swupdate*.pem certs_user/atmark-3.pem"
build_check update_certs_user.desc -- \
	"file-tar scripts_extras.tar certs_user/swupdate*.pem"

build_fail ../examples/initial_setup.desc
build_fail files_os_nonabs_fail.desc
build_fail files_dotdot_fail.desc
echo 'swdesc_command true' | name="no version" build_fail -
echo 'swdesc_option CONTAINER_CLEAR' | name="no command" build_fail -

printf "%s\n" "swdesc_command --version boot 1 true" \
	| name="special_versions" build_fail -
# note: ../imx-boot_armadillo_x2 is created by tests/examples.sh,
# which should have run before this
if [ -e ../imx-boot_armadillo_x2 ]; then
	printf "%s\n" "swdesc_boot --version test 1 ../imx-boot_armadillo_x2" \
		| name="special_versions" build_fail -
fi
printf "%s\n" "swdesc_command --version base_os 3.19.1-at.1 true" \
	| name="special_versions" build_fail -
printf "%s\n" "swdesc_tar --version base_os 3.19.1-at.1 build_tests.sh" \
	| name="special_versions" build_check -
printf "%s\n" "swdesc_tar --version base_os 3.19.1-at.1 build_tests.sh" \
	"swdesc_option version=3.19.1-at.1" \
	"swdesc_tar --base-os run.sh" \
	| name="special_versions" build_check - 2> out/special_versions.stderr
grep Warning out/special_versions.stderr \
	|| error "no warning on multiple base_os"
printf "%s\n" "swdesc_files --version cont 1 build_tests.sh" \
		"swdesc_tar --version base_os 3.19.1-at.1 build_tests.sh" \
	| name="special_versions" build_check - 2> out/special_versions.stderr
grep Warning out/special_versions.stderr \
	&& error "Should be no warning for cont+base_os"
printf "%s\n" "swdesc_command --version extra_os.cont 1 true" \
		"swdesc_tar --version base_os 3.19.1-at.1 build_tests.sh" \
	| name="special_versions" build_check - 2> out/special_versions.stderr
grep Warning out/special_versions.stderr \
	|| error "no warning on extra_os + base_os"

printf "%s\n" "swdesc_option version=1" "swdesc_command true" "swdesc_option PUBLIC" \
	| name="public after swdesc_xxx" build_fail -
printf "%s\n" "swdesc_option version=1 PUBLIC" "swdesc_command true" \
	| MKSWU_ENCRYPT_KEYFILE=$PWD/out/swupdate.aes-key name="public" build_check - -- \
	"swdesc_absent 'ivt ='"
MKSWU_PUBKEY=../swupdate-onetime-public.pem "$MKSWU" \
	--internal verify out/.public/sw-description \
	|| error "public was not signed with onetime key"

version_fail() {
	printf "%s\n" "swdesc_command --version ${*@Q} 'echo ok'" \
		| name="version $*" build_fail -
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

build_check hardlink_order.desc --
[ "$(cpio --quiet -t < out/hardlink_order.swu)" = "sw-description
sw-description.sig
zst.scripts_pre.sh
hardlink
zst.scripts_post.sh" ] || error "cpio content was not in expected order: $(cpio --quiet -t < out/hardlink_order.swu)"

build_check cmd_description.desc -- \
	"swdesc '# mkswu_orig_cmd swdesc_command_nochroot --description' \
		'description: \"some description\";'"
if command -v gawk || command -v awk && ! awk -W version | grep -q mawk; then
	"$MKSWU" --show "out/cmd_description.swu" \
		| sed -e 's/\(Built with mkswu\) .*/\1/' > "out/cmd_description.show"
	diff -u "cmd_description.show" "out/cmd_description.show" \
		|| error "mkswu --show output not as expected"
fi

rm -rf "$TESTS_DIR/out/init" "$TESTS_DIR/out/init_noupdate" "$TESTS_DIR/out/init_noatmark"
"$MKSWU" --config-dir "$TESTS_DIR/out/init" --init <<EOF \
	|| error "mkswu --init failed"
cn
privkeypass
privkeypass



somepass
differentpass(ask again)
root
le8p@ss
root_testpass
root_testpass
atmark_testpass
atmark_testpass
y

abosweb_testpass
abosweb_testpass
EOF
"$MKSWU" --config-dir "$TESTS_DIR/out/init_noupdate" --init <<EOF \
	|| error "mkswu --init noupdate failed"

cn(empty=should reask)
somepass
differentpass(ask again)




root_testpass
root_testpass
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

root_testpass
root_testpass


abosweb_testpass
abosweb_testpass
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
grep -q abos-web "$TESTS_DIR/out/init_noupdate/initial_setup.desc" \
	&& error "abosweb password set when it shouldn't be touched"
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
	local hash_desc check salt

	if [ -z "$pass" ]; then
		grep -qE "^[^#]*\"usermod -L $user\"" "$TESTS_DIR/out/$dir/initial_setup.desc" \
			|| error "$user not locked in $dir"
		return
	fi

	hash_desc=$(sed -ne "s/^[^#]*'\"'\(.*\)'\"'.*$user.*/\1/p" "$TESTS_DIR/out/$dir/initial_setup.desc")
	salt="${hash_desc#'$'*'$'}"
	salt="${salt%%'$'*}"
	check=$(printf "%s" "$pass" | openssl passwd -6 -stdin -salt "$salt")
	[ "$hash_desc" = "$check" ] || error "Error: $pass was invalid (got $hash_desc expected $check for $dir)"
}
checkpass init atmark atmark_testpass
checkpass init root root_testpass
checkpass init abos-web-admin abosweb_testpass
checkpass init_noupdate atmark
checkpass init_noupdate root root_testpass
# init_noatmark: abos-web-admin untouched
checkpass init_noatmark atmark ''
checkpass init_noatmark root root_testpass
checkpass init_noatmark abos-web-admin abosweb_testpass

# test atmark pass is regenerated on old version
sed -i -e 's/version=[0-9]/version=1/' \
	-e '/id abos-web-admin/,/usermod.*abos-web/d' \
	"$TESTS_DIR/out/init/initial_setup.desc"
"$MKSWU" --config-dir "$TESTS_DIR/out/init" --init <<EOF \
	|| error "mkswu --init on old version failed"


abosweb_testpass
abosweb_testpass
EOF
# atmark pass and confirm; empty = lock
grep -q "usermod -L atmark" "$TESTS_DIR/out/init/initial_setup.desc" \
	|| error "atmark account not locked after second init"
grep -q 'abos-web' "$TESTS_DIR/out/init/initial_setup.desc" \
	|| error "abos-web not disabled after update"
checkpass init abos-web-admin abosweb_testpass

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
