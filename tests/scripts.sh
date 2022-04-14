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
SCRIPTSDIR=./out/scripts
TMPDIR="$SCRIPTSDIR"
rm -rf "$SCRIPTSDIR"
mkdir -p "$SCRIPTSDIR"
touch "$TMPDIR/sw-description"

test_version_update() {
	SWDESC="$SCRIPTSDIR/swdesc"
	system_versions="$SCRIPTSDIR/sw-versions"
	merged="$SCRIPTSDIR/sw-versions.merged"
	board="iot-g4-es1"
	cp "scripts/sw-versions" "$SCRIPTSDIR/" \
		|| error "Source versions not found?"

	echo "Test getting version from existing file (different format)"
	version=$(get_version extra_os.kernel "$system_versions")
	[ "$version" = "5.10.90-1" ] || error "Could not get system version"

	echo "Testing version merging works"
	echo "  #VERSION extra_os.kernel 5.10.82-1 different *" > "$SWDESC"
	gen_newversion
	version=$(get_version extra_os.kernel)
	[ "$version" = "5.10.82-1" ] || error "Could not get version"
	version=$(get_version --install-if extra_os.kernel)
	[ "$version" = "5.10.82-1 different" ] || error "Could not get install-if"
	version=$(get_version extra_os.kernel "$merged")
	[ "$version" = "5.10.82-1" ] || error "Did not merge in new kernel version (different)"

	echo "  #VERSION extra_os.kernel 5.10.82-1 higher *" > "$SWDESC"
	gen_newversion
	version=$(get_version extra_os.kernel "$merged")
	[ "$version" = "5.10.90-1" ] || error "Merged new kernel version when it shouldn't have"

	echo "  #VERSION extra_os.kernel 5.10.99-1 higher *" > "$SWDESC"
	gen_newversion
	version=$(get_version extra_os.kernel "$merged")
	[ "$version" = "5.10.99-1" ] || error "Did not merge in new kernel version (higher)"

	echo "  #VERSION boot 2020.04-at2 different *" > "$SWDESC"
	gen_newversion
	version=$(get_version boot "$merged")
	[ "$version" = "2020.04-at2" ] || error "Did not merge new boot version"
	version=$(get_version other_boot "$merged")
	[ "$version" = "2020.04-at0" ] || error "other_boot should stay at old boot"

	cp "$merged" "$system_versions"
	gen_newversion
	version=$(get_version boot "$merged")
	[ "$version" = "2020.04-at2" ] || error "boot somehow changed?"
	version=$(get_version other_boot "$merged")
	[ "$version" = "2020.04-at2" ] || error "other_boot did not tickle down"

	sed -i -e '/boot/d' "$system_versions"
	gen_newversion
	version=$(get_version boot "$merged")
	[ "$version" = "2020.04-at2" ] || error "boot was not added"
	version=$(get_version other_boot "$merged")
	[ "$version" = "" ] || error "other_boot somehow got made up?"

	cp "$merged" "$system_versions"
	gen_newversion
	version=$(get_version boot "$merged")
	[ "$version" = "2020.04-at2" ] || error "boot somehow changed?"
	version=$(get_version other_boot "$merged")
	[ "$version" = "2020.04-at2" ] || error "other_boot did not tickle down"

	cp "$merged" "$system_versions"
	echo "  #VERSION boot 2020.04-at3 different $board" > "$SWDESC"
	echo "  #VERSION boot 2020.04-at4 different not-$board" >> "$SWDESC"
	gen_newversion
	version=$(get_version boot "$merged")
	[ "$(grep -cw boot "$merged")" = 1 ] || error "Duplicated boot version (ignored board)"
	[ "$version" = "2020.04-at3" ] || error "Did not merge correct new boot version"
	version=$(get_version other_boot "$merged")
	[ "$version" = "2020.04-at2" ] || error "other_boot should not stay at previous boot value"

	: > "$system_versions"
	gen_newversion
	version=$(get_version boot "$merged")
	[ "$(grep -cw boot "$merged")" = 1 ] || error "Duplicated boot version (ignored board)"
	[ "$version" = "2020.04-at3" ] || error "Did not merge correct new boot version"
	version=$(get_version other_boot "$merged")
	[ -z "$version" ] || error "other_boot should not be set"
}

# test user copy on rootfs
test_passwd_update() {
	echo "passwd copy: test normal, OK copy, no extra user"
	for f in passwd shadow group; do
		cp ./scripts/$f "$SCRIPTSDIR/$f-target"
	done
	PASSWD=./scripts/passwd
	NPASSWD="$SCRIPTSDIR/passwd-target"
	SHADOW=./scripts/shadow-set
	NSHADOW="$SCRIPTSDIR/shadow-target"
	GROUP=./scripts/group
	NGROUP="$SCRIPTSDIR/group-target"

	( update_shadow; ) || error "Normal copy failed"


	echo "passwd copy: test not overriding passwd already set"
	sed -i -e 's/root:[^:]*/root:GREPMEFAKE/' "$SCRIPTSDIR/shadow-target"

	( update_shadow; ) || error "copy already set failed"
	grep -q 'root:GREPMEFAKE' "$SCRIPTSDIR/shadow-target" || error "password was overriden"


	echo "passwd copy: test leaving empty passwords fail"
	for f in passwd shadow group; do
		cp ./scripts/$f "$SCRIPTSDIR/$f-target"
	done
	SHADOW=./scripts/shadow
	( update_shadow; ) && error "copy should have failed"


	echo "passwd copy: test adding new user"
	for f in passwd shadow group; do
		cp ./scripts/$f "$SCRIPTSDIR/$f-extrauser"
		cp ./scripts/$f "$SCRIPTSDIR/$f-target"
	done
	cp ./scripts/shadow-set "$SCRIPTSDIR/shadow-extrauser"
	echo 'newuser:x:1001:' >> "$SCRIPTSDIR/group-extrauser"
	echo 'newuser:$6$KWAyQefP7vuRXJyv$Dry6v157pvQgVA/VVTkMd6gygzooCTG1ogN6XNrGi0BHCZs.MuUSlT5Mal9SoPBP97wtKm63ZlGoErZ/JnTFV0:18908:0:99999:7:::' >> "$SCRIPTSDIR/shadow-extrauser"
	echo 'newuser:x:1001:1001:test user:/home/newuser:/bin/ash' >> "$SCRIPTSDIR/passwd-extrauser"
	PASSWD="$SCRIPTSDIR/passwd-extrauser"
	SHADOW="$SCRIPTSDIR/shadow-extrauser"
	GROUP="$SCRIPTSDIR/group-extrauser"
	( update_shadow; ) || error "copy with newuser failed"
	grep -q newuser "$SCRIPTSDIR/passwd-target" || error "newuser not copied (passwd)"
	grep -q newuser "$SCRIPTSDIR/shadow-target" || error "newuser not copied (shadow)"
	grep -q newuser "$SCRIPTSDIR/group-target" || error "newuser not copied (group)"

	echo "passwd copy: test running again with new user already existing"
	( update_shadow; ) || error "copy with newuser again failed"


	echo "passwd copy: test leaving empty passwords is ok with debug set"
	for f in passwd shadow group; do
		cp ./scripts/$f "$SCRIPTSDIR/$f-target"
	done
	SHADOW=./scripts/shadow
	echo "ALLOW_EMPTY_LOGIN" > "$SCRIPTSDIR/swdesc"
	( SWDESC="$SCRIPTSDIR/swdesc" update_shadow; ) \
		|| error "should be no failure with allow empty login"
}


test_cert_update() {
	SWUPDATE_PEM="$SCRIPTSDIR/swupdate.pem"

	echo "swupdate certificate: default setup fails"
	cat "$SCRIPTS_SRC_DIR/../swupdate-onetime-public.pem" > "$SWUPDATE_PEM"
	( update_swupdate_certificate; ) && error "certificate update should have failed"

	echo "swupdate certificate: default setup with allow OK"
	cat "$SCRIPTS_SRC_DIR/../swupdate-onetime-public.pem" > "$SWUPDATE_PEM"
	echo "ALLOW_PUBLIC_CERT" > "$SCRIPTSDIR/swdesc"
	( SWDESC="$SCRIPTSDIR/swdesc" update_swupdate_certificate; ) \
		|| error "should be ok with allow public cert"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "1" ] \
		|| error "should not have removed public key"

	echo "swupdate certificate: test with other key"
	openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp256k1 \
		-keyout "$SCRIPTSDIR/key" -out "$SCRIPTSDIR/pub" -subj "/O=SWUpdate/CN=test" \
		-nodes || error "Could not generate new key"
	cat "$SCRIPTS_SRC_DIR/../swupdate-onetime-public.pem" > "$SWUPDATE_PEM"
	cat "$SCRIPTSDIR/pub" >> "$SWUPDATE_PEM"
	( update_swupdate_certificate; ) \
		|| error "certificate update should be ok with new key"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "1" ] \
		|| error "should have removed public key"

	echo "swupdate certificate: test with other key, again"
	( update_swupdate_certificate; ) \
		|| error "certificate update should be ok with new key"
	[ "$(grep -c "BEGIN CERT" "$SWUPDATE_PEM")" = "1" ] \
		|| error "should have removed public key"
}

test_preserve_files_post() {
	TARGET=$(realpath -m "$SCRIPTSDIR/target")
	SRC=$(realpath -m "$SCRIPTSDIR/src")
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

test_preserve_files_pre() {
	TARGET=$(realpath -m "$SCRIPTSDIR/target")
	SRC=$(realpath -m "$SCRIPTSDIR/src")
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
	atlog="$SCRIPTSDIR/atlog"
	old_versions="$SCRIPTSDIR/old_versions"
	new_versions="$SCRIPTSDIR/new_versions"
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
	file="$SCRIPTSDIR/swupdate_preserve_files"

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
	file="$SCRIPTSDIR/swupdate_overlays"

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

	# check script was kept up to date and regen diff
	diff -u ../examples/update_preserve_files.sh ../examples/update_overlays.sh \
			| grep -vE '^@@' | tail -n +3 \
		> "$SCRIPTSDIR/update_scripts_diff.diff"
	FAIL=""
	cmp -s "update_scripts_diff.diff" "$SCRIPTSDIR/update_scripts_diff.diff" \
		|| FAIL=1
	mv "$SCRIPTSDIR/update_scripts_diff.diff" "update_scripts_diff.diff"
	[ -z "$FAIL" ] || error "update_preserve_files or overlays got modified without keeping in sync, check diff"
}

# run in subshell as we cannot source all at once
(
	set -e
	. "$SCRIPTS_SRC_DIR/common.sh"
	cleanup() { :; }
	. "$SCRIPTS_SRC_DIR/versions.sh"
	test_version_update
) || error "versions test failed"

(
	set -e
	. "$SCRIPTS_SRC_DIR/common.sh"
	cleanup() { :; }
	. "$SCRIPTS_SRC_DIR/post_rootfs.sh"
	test_passwd_update
	test_cert_update
	test_preserve_files_post
) || error "post test failed"

(
	set -e
	. "$SCRIPTS_SRC_DIR/common.sh"
	cleanup() { :; }
	. "$SCRIPTS_SRC_DIR/pre_rootfs.sh"
	test_preserve_files_pre
) || error "pre test failed"

(
	set -e
	. "$SCRIPTS_SRC_DIR/common.sh"
	needs_reboot() { return 0; }
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
