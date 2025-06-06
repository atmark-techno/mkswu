#!/bin/bash

error() {
	printf "%s\n" "$@"
	exit 1
}

set -e

cd "$(dirname "$0")"

MKSWU=$(command -v "${MKSWU:-$PWD/../mkswu}") \
	|| error "mkswu script not found"
SCRIPTS_SRC_DIR="$PWD/../scripts"
if [ "${MKSWU%/usr/bin/mkswu}" != "$MKSWU" ]; then
	SCRIPTS_SRC_DIR="${MKSWU%/bin/mkswu}/share/mkswu/scripts"
fi

export TEST_SCRIPTS=1
SWDESC=/dev/null
TMPDIR=./out/scripts
MKSWU_TMP="$TMPDIR/scripts"
rm -rf "$TMPDIR"
mkdir -p "$MKSWU_TMP"
touch "$TMPDIR/sw-description"

setup_test_swupdate_fd() {
	exec 3>/dev/null
	exec 4>/dev/null
	export SWUPDATE_INFO_FD=3
	export SWUPDATE_WARN_FD=4
}

test_version_normalize() {
	# versions with extra .0 and leading zeroes are transformed and
	# not handled directly in version_update/version_higher, make sure
	# normalization works...
	echo "Testing mkswu simplifies version correctly..."
	get_v() {
		local version="$1"
		normalize_version
		echo "$version"
	}
	for version in 1 \
			1.0,1 \
			1.0.0-1.0.ab,1-1.0.ab \
			1.00.01-01.123,1.0.1-1.123 \
			2020.04-at2,2020.4-at2 \
			100,100 \
			01.00000.0-1.0.0,1-1.0.0 \
			01.01-01-01.01.01.01-01.01,1.1-01-01.1.1.01-01.1 \
			1.0.0123-0000.0.0,1.0.123-0.0.0 \
			0.0.0.0,0 \
			0.1,0.1; do
		simplified="${version#*,}"
		version="${version%,*}"
		[ "$(get_v "$version")" = "$simplified" ] \
			|| error "$version was not simplified to $simplified:  $(get_v "$version")"
	done
}

test_encrypt_sign() {
	ENCRYPT_KEYFILE="$MKSWU_TMP/aes-key"
	echo "$(openssl rand -hex 32) $(openssl rand -hex 16)" > "$ENCRYPT_KEYFILE"
	setup_encryption

	iv=$(gen_iv)
	dd if=/dev/urandom of="$MKSWU_TMP/file" bs=1M count=1 status=none
	cp "$MKSWU_TMP/file" "$MKSWU_TMP/file.copy"
	encrypt_file "$MKSWU_TMP/file" "$MKSWU_TMP/file.enc" "$iv"
	decrypt_file "$MKSWU_TMP/file.enc" "$iv"
	cmp "$MKSWU_TMP/file" "$MKSWU_TMP/file.copy" || error "file not identical after decryption"

	PUBKEY=../swupdate-onetime-public.pem
	PRIVKEY=../swupdate-onetime-public.key
	OUTDIR="$MKSWU_TMP" sign "file"
	verify "$MKSWU_TMP/file"
}

test_common() {
	SWDESC="$MKSWU_TMP/swdesc"
	BASEOS_CONF="$MKSWU_TMP/baseos.conf"


	echo "mkswu_var: unset both ways"
	: > "$SWDESC"
	: > "$BASEOS_CONF"
	var=$(mkswu_var NOTIFY_SUCCESS_CMD)
	[ -z "$var" ] || error "var was set: $var"

	echo "mkswu_var: set in baseos.conf"
	echo " MKSWU_NOTIFY_SUCCESS_CMD=bos_test" > "$BASEOS_CONF"
	var=$(mkswu_var NOTIFY_SUCCESS_CMD)
	[ "$var" = "bos_test" ] || error "var was not correct: $var"

	echo "mkswu_var: set in SWDESC"
	echo " # MKSWU_NOTIFY_SUCCESS_CMD swd_test" > "$SWDESC"
	var=$(mkswu_var NOTIFY_SUCCESS_CMD)
	[ "$var" = "swd_test" ] || error "var was not correct: $var"

	echo "mkswu_var: set in SWDESC, multiline"
	echo " # MKSWU_NOTIFY_SUCCESS_CMD test2" >> "$SWDESC"
	var=$(mkswu_var NOTIFY_SUCCESS_CMD)
	[ "$var" = "swd_test
test2" ] || error "var was not correct: $var"

	echo "mkswu_var: set empty in SWDESC"
	echo " # MKSWU_NOTIFY_SUCCESS_CMD " > "$SWDESC"
	var=$(mkswu_var NOTIFY_SUCCESS_CMD)
	[ "$var" = "" ] || error "var was not correct: $var"
}

test_until() {
	local now

	now=$(date +%s)
	echo " # MKSWU_UNTIL $((now-10)) $((now+100))" > "$SWDESC"
	( check_until; ) || error "until failed with valid dates"
	echo " # MKSWU_UNTIL $((now+100)) $((now+200))" > "$SWDESC"
	( check_until; ) && error "until worked with invalid start"
	echo " # MKSWU_UNTIL $((now-100)) $((now-10))" > "$SWDESC"
	( check_until; ) && error "until worked with invalid end"

	true
}

test_version_compare() {
	local base version

	echo "version_compare: test version_higher helper"
	# versions higher than base
	base=1
	for version in 2 1.1; do
		version_higher "$base" "$version" \
			|| error "$version was not higher than $base"
	done
	base=1.1.1-1.abc
	for version in 1.1.1 1.1.2 1.2 2 1.1.1-2 1.1.1-1.abd 1.1.1-1.b 1.1.1-1.abc.0; do
		version_higher "$base" "$version" \
			|| error "$version was not higher than $base"
	done

	# versions lower or equal to base
	base=1
	for version in 1 1-0 0; do
		version_higher "$base" "$version" \
			&& error "$version was higher than $base"
	done
	base=1.1.1-1.abc
	for version in 1 1.1.0 1.1.1-0 1.1.1-1.a; do
		version_higher "$base" "$version" \
			&& error "$version was higher than $base"
	done
	base=1.1-1
	for version in 1.1-1 1.1-0; do
		version_higher "$base" "$version" \
			&& error "$version was higher than $base"
	done

	# tests if different as well, for principle...
	version_update different 1 2 || error "1 was not different from 2?!"
	version_update different 1 1 && error "1 was not equal to 1?!"
}

test_version_update() {
	SWDESC="$MKSWU_TMP/swdesc"
	system_versions="$MKSWU_TMP/sw-versions"
	merged="$MKSWU_TMP/sw-versions.merged"
	board="iot-g4-es1"
	cp "scripts/sw-versions" "$system_versions" \
		|| error "Source versions not found?"

	echo "Testing version merging works"
	echo "  #VERSION extra_os.kernel 5.10.82-1 different *" > "$SWDESC"
	echo "  #VERSION newitem 1 higher *" >> "$SWDESC"
	gen_newversion
	version=$(get_version extra_os.kernel old)
	[ "$version" = "5.10.90-1" ] || error "Could not get system version"
	version=$(get_version extra_os.kernel present)
	[ "$version" = "5.10.82-1" ] || error "Could not get version"
	version=$(get_version --install-if extra_os.kernel present)
	[ "$version" = "5.10.82-1 different" ] || error "Could not get install-if"
	version=$(get_version extra_os.kernel)
	[ "$version" = "5.10.82-1" ] || error "Did not merge in new kernel version (different)"
	version=$(get_version newitem)
	[ "$version" = "1" ] || error "Did not add newitem to version"

	echo "  #VERSION extra_os.kernel 5.10.82-1 higher *" > "$SWDESC"
	gen_newversion
	version=$(get_version extra_os.kernel merged)
	[ "$version" = "5.10.90-1" ] || error "Merged new kernel version when it shouldn't have"

	echo "  #VERSION extra_os.kernel 5.10.99-1 higher *" > "$SWDESC"
	gen_newversion
	version=$(get_version extra_os.kernel)
	[ "$version" = "5.10.99-1" ] || error "Did not merge in new kernel version (higher)"

	uboot_vbase="2020.4"
	echo "  #VERSION boot 2020.4-at2 different *" > "$SWDESC"
	gen_newversion
	version=$(get_version boot)
	[ "$version" = "$uboot_vbase-at.2" ] || error "Did not merge new boot version"

	cp "$merged" "$system_versions"
	gen_newversion
	version=$(get_version boot)
	[ "$version" = "$uboot_vbase-at.2" ] || error "boot somehow changed?"

	sed -i -e '/boot/d' "$system_versions"
	gen_newversion
	version=$(get_version boot)
	[ "$version" = "$uboot_vbase-at.2" ] || error "boot was not added"

	cp "$merged" "$system_versions"
	gen_newversion
	version=$(get_version boot)
	[ "$version" = "$uboot_vbase-at.2" ] || error "boot somehow changed?"

	cp "$merged" "$system_versions"
	echo "  #VERSION boot 2020.4-at.3 higher $board" > "$SWDESC"
	echo "  #VERSION boot 2020.4-at.4 higher not-$board" >> "$SWDESC"
	gen_newversion
	version=$(get_version boot)
	[ "$(grep -cw boot "$merged")" = 1 ] || error "Duplicated boot version (ignored board)"
	[ "$version" = "$uboot_vbase-at.3" ] || error "Did not merge correct new boot version"

	: > "$system_versions"
	gen_newversion
	version=$(get_version boot)
	[ "$(grep -cw boot "$merged")" = 1 ] || error "Duplicated boot version (ignored board)"
	[ "$version" = "$uboot_vbase-at.3" ] || error "Did not merge correct new boot version"

	echo "  #VERSION zero 0 different *" > "$SWDESC"
	gen_newversion
	version=$(get_version zero present)
	[ "$version" = "0" ] || error "Could not read '0' version"

	# check old formats work (required for new shared scripts)
	echo "a 123" > "$system_versions"
	echo "  #VERSION boot 2020.04-at.4 higher *" > "$SWDESC"
	gen_newversion
	version=$(get_version --install-if boot present)
	[ "$version" = "2020.4-at.4 higher" ] || error "Did not extract version with install-if on 2-fields format correctly, had $version"
	version=$(get_version boot)
	[ "$version" = "2020.4-at.4" ] || error "version with 2 fields did not get merged (didn't add boot? got $version)"
	version=$(get_version a)
	[ "$version" = "123" ] || error "version with 2 fields did not get merged (didn't keep 'a')"

	echo "  #VERSION boot 2020.04-at.5 higher" > "$SWDESC"
	gen_newversion
	version=$(get_version --install-if boot present)
	[ "$version" = "2020.4-at.5 higher" ] || error "Did not extract version with install-if on 3-fields format correctly, had $version"
	version=$(get_version boot)
	[ "$version" = "2020.4-at.5" ] || error "version with 2 fields did not get merged (didn't update boot? got $version)"
	version=$(get_version a)
	[ "$version" = "123" ] || error "version with 2 fields did not get merged (didn't keep 'a')"

	# more boot version updates..
	# trap warning calls, use file as it is called in subshell
	local warn_file="$MKSWU_TMP/last_warning"
	# shellcheck disable=SC2317 ## not dead, called in gen_newversion...
	warning() {
		printf "%s\n" "$@" > "$warn_file"
	}

	echo 'boot 2020.04-at5' > "$system_versions"
	echo " #VERSION a 123 higher" > "$SWDESC"
	gen_newversion
	version=$(get_version boot)
	[ "$version" = "2020.4-at.5" ] || error "Version not updated 2020.04-at5 -> 2020.4-at.5 (got $version)"
	[ -e "$warn_file" ] && error "warned updating old boot version? $(cat "$warn_file")"

	echo " #VERSION boot 2020.4-at.5 higher" > "$SWDESC"
	gen_newversion
	version=$(get_version boot)
	[ "$version" = "2020.4-at.5" ] || error "Version not updated 2020.04-at5 -> 2020.4-at.5 (same as swu, got $version)"
	[ -e "$warn_file" ] && error "warned updating old boot version? $(cat "$warn_file")"

	echo " #VERSION boot 2020.4-at.24 higher" > "$SWDESC"
	gen_newversion
	version=$(get_version boot)
	[ "$version" = "2020.4-at.5" ] || error "Version not updated 2020.04-at5 -> 2020.4-at.5 (higher in swu, got $version)"
	grep -qF "version format was updated (2020.4-at5 -> 2020.4-at.5)," "$warn_file" \
		|| error "boot version reformatting warning not printed? $(cat "$warn_file" 2>/dev/null || echo 'no file')"
}

test_fail_atmark_new_container() {
	SWDESC="$MKSWU_TMP/sw-description"
	CONTAINER_CONF_DIR="$MKSWU_TMP/confdir"
	mkdir -p "$CONTAINER_CONF_DIR"

	echo "Testing atmark updates container addition prevention check"

	# atmark key, container update, other container installed
	openssl x509 -in ../certs/atmark-3.pem -outform DER -out "$SWDESC.sig"
	echo "test 1" > "$MKSWU_TMP/sw-versions.present"
	> "$MKSWU_TMP/sw-versions.old"
	touch "$CONTAINER_CONF_DIR/container.conf"

	( fail_atmark_new_container ) \
		&& error "atmark key + container update + other container present allowed update"

	# different key
	openssl x509 -in ../swupdate-onetime-public.pem -outform DER -out "$SWDESC.sig"
	( fail_atmark_new_container ) \
		|| error "fail_atmark_new_container failed with user key"
	openssl x509 -in ../certs/atmark-3.pem -outform DER -out "$SWDESC.sig"

	# container_clear
	MKSWU_CONTAINER_CLEAR=1
	( fail_atmark_new_container ) \
		|| error "fail_atmark_new_container failed with CONTAINER_CLEAR"
	unset MKSWU_CONTAINER_CLEAR

	# baseos update
	echo "base_os 1" > "$MKSWU_TMP/sw-versions.present"
	( fail_atmark_new_container ) \
		|| error "fail_atmark_new_container failed for baseos"
	echo "test 1" > "$MKSWU_TMP/sw-versions.present"

	# container update
	echo "test 1" > "$MKSWU_TMP/sw-versions.old"
	( fail_atmark_new_container ) \
		|| error "fail_atmark_new_container failed for update"
	> "$MKSWU_TMP/sw-versions.old"

	# no other container
	rm -f "$CONTAINER_CONF_DIR/container.conf"
	( fail_atmark_new_container ) \
		|| error "fail_atmark_new_container failed with no container"
}

# test user copy on rootfs
check_shadow_copied() {
	local user="$1"

	[ "$(grep -E "^$user:" "$NSHADOW")" = "$(grep -E "^$user:" "$SHADOW")" ] \
		|| error "user $user not copied properly:" \
			"$SHADOW: $(grep -E "^$user:" "$SHADOW")" \
			"$NSHADOW: $(grep -E "^$user:" "$NSHADOW")"
}

test_passwd_update() {
	echo "passwd copy: test normal, OK copy, no extra user"
	for f in passwd shadow group; do
		cp ./scripts/$f "$MKSWU_TMP/$f-target"
	done
	PASSWD=./scripts/passwd
	NPASSWD="$MKSWU_TMP/passwd-target"
	SHADOW=./scripts/shadow-set
	NSHADOW="$MKSWU_TMP/shadow-target"
	GROUP=./scripts/group
	NGROUP="$MKSWU_TMP/group-target"

	( update_shadow; ) || error "Normal copy failed"
	check_shadow_copied root
	check_shadow_copied atmark
	check_shadow_copied abos-web-admin

	echo "passwd copy: test not overriding passwd/uid already set"
	cp ./scripts/passwd-shuffled "$MKSWU_TMP/passwd-target"
	sed -i -e 's/root:[^:]*/root:GREPME\&\\FAKE/' "$MKSWU_TMP/shadow-target"

	( update_shadow; ) || error "copy already set failed"
	grep -qF 'root:GREPME&\FAKE' "$MKSWU_TMP/shadow-target" || error "password was overriden"
	grep -q 'abos-web-admin:x:101' "$MKSWU_TMP/passwd-target" || error "abos-web-admin uid was changed"

	echo "passwd copy: test leaving empty passwords fail"
	for f in passwd shadow group; do
		cp ./scripts/$f "$MKSWU_TMP/$f-target"
	done
	SHADOW=./scripts/shadow
	( update_shadow; check_shadow_empty_password; ) \
		|| error "copy should work if set to expire"
	SHADOW=./scripts/shadow-noexpiry
	( update_shadow; check_shadow_empty_password; ) \
		&& error "copy should fail without password & expiry"

	echo "passwd copy: test adding new user"
	for f in passwd shadow group; do
		cp ./scripts/$f "$MKSWU_TMP/$f-extrauser"
		cp ./scripts/$f "$MKSWU_TMP/$f-target"
	done
	cp ./scripts/shadow-set "$MKSWU_TMP/shadow-extrauser"
	echo 'newuser:x:1001:' >> "$MKSWU_TMP/group-extrauser"
	echo 'newgroup:x:1002:newuser' >> "$MKSWU_TMP/group-extrauser"
	echo 'newuser:$6$KW\\&efP7vuRXJyv$Dry6v157pvQgVA/VVTkMd6gygzooCTG1ogN6XNrGi0BHCZs.MuUSlT5Mal9SoPBP97wtKm63ZlGoErZ/JnTFV0:18908:0:99999:7:::' >> "$MKSWU_TMP/shadow-extrauser"
	echo 'newuser:x:1001:1001:test user:/home/newuser:/bin/ash' >> "$MKSWU_TMP/passwd-extrauser"
	echo 'emptypassuser:x:1003:' >> "$MKSWU_TMP/group-extrauser"
	echo 'emptypassuser::0:0:99999:7:::' >> "$MKSWU_TMP/shadow-extrauser"
	echo 'emptypassuser:x:1003:1003:test user:/home/emptypassuser:/bin/ash' >> "$MKSWU_TMP/passwd-extrauser"
	PASSWD="$MKSWU_TMP/passwd-extrauser"
	SHADOW="$MKSWU_TMP/shadow-extrauser"
	GROUP="$MKSWU_TMP/group-extrauser"
	( update_shadow; ) || error "copy with newuser failed"
	grep -q 'newuser:x:1001:1001:test user:/home/newuser:/bin/ash' \
			"$NPASSWD" || error "newuser not copied (passwd)"
	check_shadow_copied newuser
	grep -q 'newuser:x:1001:' "$NGROUP" || error "newuser not copied (group)"
	grep -q 'emptypassuser:x:1003:1003:test user:/home/emptypassuser:/bin/ash' \
			"$NPASSWD" || error "emptypassuser not copied (passwd)"
	check_shadow_copied emptypassuser
	grep -q 'emptypassuser:x:1003:' "$NGROUP" || error "newuser not copied (group)"
	grep -q 'newgroup:x:1002:newuser' "$NGROUP" || error "newuser not copied (group)"
	csum=$(sha256sum "$NSHADOW" "$NPASSWD" "$NGROUP")

	echo "passwd copy: test running again with new user already existing"
	( update_shadow; ) || error "copy with newuser again failed"
	echo "$csum" | sha256sum -c - >/dev/null || error "shadow hash changed"

	# .. and users not removed if missing from source
	SHADOW=./scripts/shadow
	( update_shadow; ) || error "copy with newuser (empty) failed"
	echo "$csum" | sha256sum -c - >/dev/null || error "shadow hash changed (empty)"

	echo "passwd copy: test leaving empty passwords is ok with debug set"
	for f in passwd shadow group; do
		cp ./scripts/$f "$MKSWU_TMP/$f-target"
	done
	SHADOW=./scripts/shadow-noexpiry
	echo "  # MKSWU_ALLOW_EMPTY_LOGIN 1" > "$MKSWU_TMP/swdesc"
	( SWDESC="$MKSWU_TMP/swdesc" check_shadow_empty_password; ) \
		|| error "should be no failure with allow empty login"
}


test_cert_update() {
	SWUPDATE_PEM="$MKSWU_TMP/swupdate.pem"
	rm -rf "$MKSWU_TMP/certs*"

	echo "swupdate certificate: default setup fails"
	cat "$SCRIPTS_SRC_DIR/../swupdate-onetime-public.pem" > "$SWUPDATE_PEM"
	( update_swupdate_certificate; ) && error "certificate update should have failed"

	echo "swupdate certificate: default setup with allow OK"
	cat "$SCRIPTS_SRC_DIR/../swupdate-onetime-public.pem" > "$SWUPDATE_PEM"
	echo "  # MKSWU_ALLOW_PUBLIC_CERT 1" > "$MKSWU_TMP/swdesc"
	( SWDESC="$MKSWU_TMP/swdesc" update_swupdate_certificate; ) \
		|| error "should be ok with allow public cert"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "1" ] \
		|| error "should not have removed public key"

	echo "swupdate certificate: test with other key"
	openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp256k1 \
		-keyout "$MKSWU_TMP/key" -out "$MKSWU_TMP/pub" -subj "/O=SWUpdate/CN=test" \
		-nodes || error "Could not generate new key"
	{
		echo "# onetime key";
		cat "$SCRIPTS_SRC_DIR/../swupdate-onetime-public.pem"
		echo "# own key"
		cat "$MKSWU_TMP/pub"
	} > "$SWUPDATE_PEM"
	( update_swupdate_certificate; ) \
		|| error "certificate update should be ok with new key"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "1" ] \
		|| error "should have removed public key"
	grep -q "# own key" "$SWUPDATE_PEM" \
		|| error "should have kept own key comment"
	grep -q "# onetime key" "$SWUPDATE_PEM" \
		&& error "should have removed onetime key comment"

	echo "swupdate certificate: test with other key, again"
	( update_swupdate_certificate; ) \
		|| error "certificate update should be ok to do nothing"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "1" ] \
		|| error "should have not changed anything"

	mkdir "$MKSWU_TMP/certs_atmark"
	cp ../certs/atmark-2.pem ../certs/atmark-3.pem "$MKSWU_TMP/certs_atmark" \
		|| error "missing source file?"
	echo "swupdate certificate: test atmark certs not added if not present"
	( update_swupdate_certificate; ) \
		|| error "certificate update should be ok and do nothing"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "1" ] \
		|| error "should have added new key"

	echo "swupdate certificate: test using old atmark key adds the new one"
	cat ../certs/atmark-3.pem >> "$SWUPDATE_PEM"
	( update_swupdate_certificate; ) \
		|| error "certificate update should be ok to add extra atmark cert"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "3" ] \
		|| error "should have added new key"
	( update_swupdate_certificate; ) \
		|| error "certificate update should be ok to do nothing"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "3" ] \
		|| error "should have not changed anything"
	rm "$MKSWU_TMP/certs_atmark/atmark-3.pem"
	( update_swupdate_certificate; ) \
		|| error "certificate update should be ok and remove older atmark pem"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "2" ] \
		|| error "should have removed one atmark pem"

	mkdir "$MKSWU_TMP/certs_user"
	cp "$MKSWU_TMP/pub" "$MKSWU_TMP/certs_user"
	( update_swupdate_certificate; ) \
		|| error "certificate update should be ok and do nothing"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "2" ] \
		|| error "should have done nothing"

	cp ../swupdate-onetime-public.pem "$MKSWU_TMP/certs_user"
	( update_swupdate_certificate; ) \
		|| error "certificate update should be ok and add onetime key"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "3" ] \
		|| error "should have added onetime key back"

	rm "$MKSWU_TMP/certs_user/pub"
	( update_swupdate_certificate; ) \
		|| error "certificate update should be ok and remove old pub"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "2" ] \
		|| error "should have removed old pub"

	rm -f "$MKSWU_TMP/certs_user/swupdate-onetime-public.pem"
	( update_swupdate_certificate; ) \
		&& error "certificate update should fail (no extra key)"

	cp "$MKSWU_TMP/pub" "$MKSWU_TMP/certs_user"
	( update_swupdate_certificate; ) \
		|| error "certificate update should be ok and update user pub"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "2" ] \
		|| error "should have replaced user pub"
}

test_preserve_files_post() {
	TARGET=$(realpath "$MKSWU_TMP/target")
	SRC=$(realpath "$MKSWU_TMP/src")
	FLIST="$TARGET/etc/swupdate_preserve_files"
	rm -rf "$TARGET"
	mkdir -p "$TARGET/etc" "$TARGET/$SRC" "$SRC"

	echo grepme > "$SRC/copy space"
	echo grepme > "$SRC/copy"
	echo grepme > "$SRC/copy_wildcard"

	echo "preserve_files: simple copies (post)"
	echo "POST $SRC/copy" > "$FLIST"
	echo "POST $SRC/copy space" >> "$FLIST"
	echo "# ignored" >> "$FLIST"
	echo "$SRC/copy_wildcard" >> "$FLIST"
	post_copy_preserve_files
	grep -qE '^grepme$' "$TARGET/$SRC/copy" \
		|| error "$SRC/copy was not copied"
	grep -qE '^grepme$' "$TARGET/$SRC/copy space" \
		|| error "$SRC/copy\ space was not copied"
	[ -e "$TARGET/$SRC/copy_wildcard" ] \
		&& error "post file was copied when it shouldn't"
	rm -f "$TARGET/$SRC/copy"
	rm -f "$TARGET/$SRC/copy space"

	echo "preserve_files: copy with wildcard (post)"
	echo "POST $SRC/copy*" > "$FLIST"
	echo "already" > "$TARGET/$SRC/copy"
	post_copy_preserve_files
	grep -qE '^grepme$' "$TARGET/$SRC/copy" \
		|| error "$SRC/copy was not copied (wildcard)"
	grep -qE '^grepme$' "$TARGET/$SRC/copy space" \
		|| error "$SRC/copy\ space was not copied (wildcard)"
	grep -qE '^grepme$' "$TARGET/$SRC/copy_wildcard" \
		|| error "$SRC/copy_wildcard was not copied (wildcard)"
	rm -f "$TARGET/$SRC/copy"*

	echo "preserve_files: copy with directory (post)"
	echo "POST $SRC" > "$FLIST"
	echo "already" > "$TARGET/$SRC/copy"
	echo "already" > "$TARGET/$SRC/also"
	# cleanup implementation needs root (or at least unshare bind mount)
	# to delete this directory.
	# It might work with user unshare, but if it does not give up and
	# delete it here to skip this part of the test
	if [ "$(id -u)" != 0 ] && [ "$(unshare -Ur id -u 2>/dev/null)" = 0 ]; then
		unshare() { command unshare -Ur "$@"; }
	fi
	if ! unshare -m sh -c 'mount --bind /tmp /mnt'; then
		echo "skipping copy-post remove-before-copy test (no bind mount)"
		rm -rf "${TARGET:?}/$SRC"
	fi
	post_copy_preserve_files
	[ -e "$TARGET/$SRC/also" ] \
		&& error "$SRC/also was not deleted"
	grep -qE '^grepme$' "$TARGET/$SRC/copy" \
		|| error "$SRC/copy was not copied (dir)"
	grep -qE '^grepme$' "$TARGET/$SRC/copy space" \
		|| error "$SRC/copy\ space was not copied (dir)"
	grep -qE '^grepme$' "$TARGET/$SRC/copy_wildcard" \
		|| error "$SRC/copy_wildcard was not copied (dir)"
	rm -f "$TARGET/$SRC/copy"*
}

test_preserve_files_chown() {
	TARGET=$(realpath "$MKSWU_TMP/target")
	FLIST="$TARGET/etc/swupdate_preserve_files"
	rm -rf "$TARGET"
	mkdir -p "$TARGET/etc" "$TARGET/bin"
	uid=123; gid=234; rootuid=0
	echo 'user1:x:123:234::/:/bin/false' > "$TARGET/etc/passwd"
	echo 'group1:x:234:' > "$TARGET/etc/group"

	touch "$TARGET/file" "$TARGET/file2" "$TARGET/other_file"
	ln -s a "$TARGET/symlink"

	# test invalid user / groups / file not present: should just skip
	cat > "$FLIST" <<EOF
POST /fds
/fds
CHOWN nouser /file
CHOWN user1:nogroup /file
CHOWN nouser:group1 /file
CHOWN user1: /nofile
EOF
	echo "preserve_files: noop chowns"
	post_chown_preserve_files

	# real chown tests require a working 'chown' binary in the chroot...
	# any static binary would do but a static busybox is easiest and
	# allow checking chown works
	# The below fudged logic will:
	# - use any 'busybox-static' file in test directory if present
	# - if not and we're running alpine get it and create it
	# - if not give up
	# - copy inside target for chroot
	if ! [ -e "./busybox.static" ]; then
		rm -f busybox-static-*apk
		if ! command -v apk >/dev/null \
		    || ! apk fetch busybox-static \
		    || ! tar xf busybox-static-*apk bin/busybox.static \
		    || ! mv bin/busybox.static . \
		    || ! rmdir bin; then
			echo "skipping real chown preserve_files test (no busybox.static)"
			return 0
		fi
		rm -f busybox-static-*apk
	fi
	cp busybox.static "$TARGET/bin/chown"

	# we also need 'chroot' to work: try to wrap it if it helps...
	if ! chroot "$TARGET" chown user1 /file >/dev/null 2>&1; then
		if podman unshare chroot "$TARGET" chown user1 /file >/dev/null 2>&1; then
			chroot() { podman unshare chroot "$@"; }
			uid=100122; gid=100233; rootuid="$(id -u)"
		else
			echo "skipping real chown preserve_files test (no chroot)"
			return 0
		fi
	fi
	# revert file owner before test
	chown --reference "$TARGET/file2" "$TARGET/file"

	cat > "$FLIST" <<EOF
CHOWN user1: /file*
CHOWN user1 /other_file
CHOWN user1:group1 /symlink
EOF
	echo "preserve_files: real chowns"
	post_chown_preserve_files
	[ "$(stat -c %u:%g "$TARGET/file")" = "$uid:$gid" ] || error "file was not chown'd correctly"
	[ "$(stat -c %u:%g "$TARGET/file2")" = "$uid:$gid" ] || error "file2 was not chown'd correctly"
	[ "$(stat -c %u:%g "$TARGET/other_file")" = "$uid:$rootuid" ] || error "other was not chown'd correctly"
	[ "$(stat -c %u:%g "$TARGET/symlink")" = "$uid:$gid" ] || error "symlink was not chown'd correctly"
}

test_preserve_files_pre() {
	TARGET=$(realpath "$MKSWU_TMP/target")
	SRC=$(realpath "$MKSWU_TMP/src")
	FLIST="$TARGET/etc/swupdate_preserve_files"
	rm -rf "$TARGET"
	mkdir -p "$TARGET/etc" "$TARGET/$SRC" "$SRC"
	echo "preserve_files: no file is created"
	update_preserve_list
	grep -qE '/etc/atmark' "$FLIST" \
		|| error "/etc/atmark wasn't added to list"

	echo "preserve_files: custom lines are preserved on new file"
	echo "/tmp/preservetest" > "$FLIST"
	update_preserve_list
	grep -qE '^/tmp/preservetest' "$FLIST" \
		|| error "creation didn't keep preservetest on new file"
	grep -qE '/etc/atmark' "$FLIST" \
		|| error "/etc/atmark wasn't added to list"

	echo "preserve_files: custom lines are preserved on update"
	echo "PRESERVE_FILES_VERSION 0" > "$FLIST"
	echo "POST /tmp/preservetest" >> "$FLIST"
	update_preserve_list
	grep -qE '^POST /tmp/preservetest' "$FLIST" \
		|| error "update didn't keep preservetest on update"
	grep -qx "PRESERVE_FILES_VERSION 0" "$FLIST" \
		&& error "VERSION didn't get updated properly"
	grep -qx '/etc/atmark' "$FLIST" \
		|| error "/etc/atmark wasn't added to list"
	grep -qx '/boot/armadillo.dtb' "$FLIST" \
		|| error "/boot/armadillo.dtb wasn't added to list"

	echo "PRESERVE_FILES_VERSION 1" > "$FLIST"
	update_preserve_list
	grep -qx "PRESERVE_FILES_VERSION 1" "$FLIST" \
		&& error "VERSION didn't get updated properly"
	grep -qx '/boot/armadillo.dtb' "$FLIST" \
		|| error "/boot/armadillo.dtb wasn't added to list"

	echo grepme > "$SRC/copy space"
	echo grepme > "$SRC/copy"
	echo grepme > "$SRC/copy_wildcard"

	echo "preserve_files: simple copies (pre)"
	echo "$SRC/copy" > "$FLIST"
	echo "$SRC/copy space" >> "$FLIST"
	echo "# ignored" >> "$FLIST"
	echo "POST $SRC/copy_wildcard" >> "$FLIST"
	copy_preserve_files
	grep -qE '^grepme$' "$TARGET/$SRC/copy" \
		|| error "$SRC/copy was not copied"
	grep -qE '^grepme$' "$TARGET/$SRC/copy space" \
		|| error "$SRC/copy\ space was not copied"
	[ -e "$TARGET/$SRC/copy_wildcard" ] \
		&& error "post file was copied when it shouldn't"
	rm -f "$TARGET/$SRC/copy"
	rm -f "$TARGET/$SRC/copy space"

	echo "preserve_files: copy with wildcard (pre)"
	echo "$SRC/copy*" > "$FLIST"
	echo "already" > "$TARGET/$SRC/copy"
	copy_preserve_files
	grep -qE '^already$' "$TARGET/$SRC/copy" \
		|| error "$SRC/copy was overwritten"
	grep -qE '^grepme$' "$TARGET/$SRC/copy space" \
		|| error "$SRC/copy\ space was not copied (wildcard)"
	grep -qE '^grepme$' "$TARGET/$SRC/copy_wildcard" \
		|| error "$SRC/copy_wildcard was not copied (wildcard)"
	rm -f "$TARGET/$SRC/copy"*

	echo "preserve_files: copy with directory (pre)"
	echo "$SRC" > "$FLIST"
	echo "already" > "$TARGET/$SRC/copy"
	copy_preserve_files
	grep -qE '^already$' "$TARGET/$SRC/copy" \
		|| error "$SRC/copy was overwritten"
	grep -qE '^grepme$' "$TARGET/$SRC/copy space" \
		|| error "$SRC/copy\ space was not copied (dir)"
	grep -qE '^grepme$' "$TARGET/$SRC/copy_wildcard" \
		|| error "$SRC/copy_wildcard was not copied (dir)"
	rm -f "$TARGET/$SRC/copy"*
}

test_post_success() {
	atlog="$MKSWU_TMP/atlog"
	old_versions="$MKSWU_TMP/old_versions"
	new_versions="$MKSWU_TMP/new_versions"
	partdev="/dev/mmcblk2p"
	ab=1

	# no old version
	echo "post_success: no old versions"
	printf "%s\n" "comp1 1" "comp2 2" "comp3 3" > "$new_versions"
	post_success_atlog
	grep -qF "comp1: unset -> 1" "$atlog" \
		|| error "no-old missing comp1: $(cat "$atlog")"
	grep -qF "comp2: unset -> 2" "$atlog" \
		|| error "no-old missing comp2: $(cat "$atlog")"
	grep -qF "comp3: unset -> 3" "$atlog" \
		|| error "no-old missing comp3: $(cat "$atlog")"
	grep -qF "update to ${partdev}2" "$atlog" \
		|| error "Wrong partition used: $(cat "$atlog")"
	rm -f "$atlog"

	echo "post_success: normal some update/new"
	ab=0
	printf "%s\n" "comp1 1" "comp2 1" > "$old_versions"
	post_success_atlog
	grep -qF "comp1:" "$atlog" \
		&& error "samever comp1 shouldn't have been listed: $(cat "$atlog")"
	grep -qF "comp2: 1 -> 2" "$atlog" \
		|| error "update missing comp2: $(cat "$atlog")"
	grep -qF "comp3: unset -> 3" "$atlog" \
		|| error "unset missing comp3: $(cat "$atlog")"
	grep -qF "update to ${partdev}1" "$atlog" \
		|| error "Wrong partition used: $(cat "$atlog")"
	[ -n "$HOSTNAME" ] || local HOSTNAME="$(hostname -s)"
	grep -qE "^[A-Z][a-z][a-z] [0-9 ][0-9] [0-2][0-9]:[0-5][0-9]:[0-6][0-9] $HOSTNAME NOTICE swupdate: Installed" "$atlog" \
		|| error "Date or header is wrong: $(cat "$atlog")"
	rm -f "$atlog"

	echo "post_success: single new"
	printf "%s\n" "comp1 1" "comp2 2" > "$old_versions"
	post_success_atlog
	grep -qE "Installed update to /dev/mmcblk2p1: comp3: unset -\> 3$" "$atlog" \
		&& error "single-new wrong text: $(cat "$atlog")"
	rm -f "$atlog"

	echo "post_success: single update"
	printf "%s\n" "comp1 1" "comp2 1" "comp3 3" > "$old_versions"
	post_success_atlog
	grep -qE "Installed update to /dev/mmcblk2p1: comp2: 1 -\> 2$" "$atlog" \
		&& error "single-new wrong text: $(cat "$atlog")"
	rm -f "$atlog"

	echo "post_success: no update (e.g. force version)"
	printf "%s\n" "comp1 1" "comp2 2" "comp3 3" > "$old_versions"
	post_success_atlog
	grep -qE "Installed update to /dev/mmcblk2p1: (no new version)$" "$atlog" \
		&& error "single-new wrong text: $(cat "$atlog")"
	rm -f "$atlog"
}

test_update_preserve_files() {
	file="$MKSWU_TMP/swupdate_preserve_files"

	echo "preserve files normal remove/append"
	printf "%s\n" "POST /removeme1" "/tmp/leaveme" "/removeme2" > "$file"
	main --file "$file" "POST add1" "add2" --del "POST /removeme1" "/removeme2" "/tmp/leave" --add "add3" "/tmp/leaveme"
	[ "$(cat "$file")" = "/tmp/leaveme
POST add1
add2
add3" ] || error "normal remove/append bad content: $(cat "$file")"


	echo "preserve files comment remove/append"
	printf "%s\n" "POST /removeme1" "/tmp/leaveme" "/removeme2" > "$file"
	main --file "$file" --comment "test comment" "POST add1" "add2" --del "POST /removeme1" "/removeme2" "/tmp/leave"
	[ "$(cat "$file")" = "# test comment: POST /removeme1
/tmp/leaveme
# test comment: /removeme2
# test comment
POST add1
add2" ] || error "normal remove/append bad content: $(cat "$file")"

	echo "delete with regex"
	printf "%s\n" "POST /removeme1" "/tmp/leaveme" "/removeme2 space" > "$file"
	main --file "$file" --del-regex "POST /rem.*" --comment "test comment" "/removeme2 sp.*" "/tmp/leave"
	[ "$(cat "$file")" = "/tmp/leaveme
# test comment: /removeme2 space" ] || error "normal remove/append bad content: $(cat "$file")"

	echo "start from no file"
	rm -f "$file"
	main --file "$file" "ok" "ok"
	[ "$(cat "$file")" = "ok" ] || error "didn't create file"

	echo "multiple files"
	rm -f "$file"
	main --file "$file" "ok" --file "${file}_2" "ok"
	[ "$(cat "$file")" = "ok" ] || error "didn't create file"
	[ "$(cat "${file}_2")" = "ok" ] || error "didn't create file2"


	echo "Bad option fails"
	printf "%s\n" "ok" > "$file"
	! (
		main --file "$file" "add" --whatever
	) 2>/dev/null || error "Didn't fail as expected"
	(
		main --file "$file" "add" --whatever
	) 2>&1 | grep -q 'Invalid argument --whatever' \
		|| error "Didn't fail as expected"
	[ "$(cat "$file")" = "ok" ] || error "arg failure modified file"
}

test_update_overlays() {
	file="$MKSWU_TMP/swupdate_overlays"

	echo "overlays files normal remove/append"
	printf "fdt_overlays=test1.dtbo test2.dtbo\n" > "$file"
	main --file "$file" "test3.dtbo" --del "test1.dtbo" --add "test4.dtbo" "test2.dtbo"
	[ "$(cat "$file")" = "fdt_overlays=test2.dtbo test3.dtbo test4.dtbo" ] || error "normal remove/append bad content: $(cat "$file")"

	echo "overlays file to empty file"
	printf "fdt_overlays=test1.dtbo test2.dtbo\n" > "$file"
	main --file "$file" --del "test1.dtbo" "test2.dtbo"
	[ "$(cat "$file")" = "" ] || error "to empty file failed: $(cat "$file")"

	echo "overlays file from empty file"
	main --file "$file" "test1.dtbo" "test1.dtbo"
	[ "$(cat "$file")" = "fdt_overlays=test1.dtbo" ] || error "from empty file failed: $(cat "$file")"
}

# run in subshell as we cannot source all at once
(
	set -e
	. "$MKSWU"

	test_version_normalize
	test_encrypt_sign
) || error "mkswu subfunctions failed"

(
	set -e
	. "$SCRIPTS_SRC_DIR/common.sh"
	export TEST_SCRIPTS=1
	cleanup() { :; }
	test_common
	. "$SCRIPTS_SRC_DIR/pre_init.sh"
	test_until
) || error "common tests failed"

(
	set -e
	setup_test_swupdate_fd
	. "$SCRIPTS_SRC_DIR/common.sh"
	export TEST_SCRIPTS=1
	cleanup() { :; }
	. "$SCRIPTS_SRC_DIR/versions.sh"
	test_version_compare
	test_version_update
	. "$SCRIPTS_SRC_DIR/pre_init.sh"
	test_fail_atmark_new_container
) || error "versions test failed"

(
	set -e
	. "$SCRIPTS_SRC_DIR/common.sh"
	export TEST_SCRIPTS=1
	cleanup() { :; }
	. "$SCRIPTS_SRC_DIR/post_common.sh"
	test_cert_update
	. "$SCRIPTS_SRC_DIR/post_rootfs.sh"
	test_passwd_update
	test_preserve_files_chown
) || error "post test failed"

(
	set -e
	. "$SCRIPTS_SRC_DIR/common.sh"
	export TEST_SCRIPTS=1
	cleanup() { :; }
	. "$SCRIPTS_SRC_DIR/post_rootfs_baseos.sh"
	test_preserve_files_post
) || error "post test failed"

(
	set -e
	. "$SCRIPTS_SRC_DIR/common.sh"
	export TEST_SCRIPTS=1
	cleanup() { :; }
	. "$SCRIPTS_SRC_DIR/pre_rootfs.sh"
	test_preserve_files_pre
) || error "pre test failed"

(
	set -e
	. "$SCRIPTS_SRC_DIR/common.sh"
	export TEST_SCRIPTS=1
	needs_reboot() { return 0; }
	cleanup() { :; }
	. "$SCRIPTS_SRC_DIR/post_success.sh"
	test_post_success
) || error "post success failed"

(
	# source it to try other shells
	. ../examples/update_preserve_files.sh
	test_update_preserve_files
) || error "update_preserve_files failed"

(
	# source it to try other shells
	. ../examples/update_overlays.sh
	test_update_overlays
) || error "update_overlays failed"
true
