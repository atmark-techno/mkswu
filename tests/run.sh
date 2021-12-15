#!/bin/bash

set -ex

cd "$(dirname "$0")"

# sometimes remove tests/out directory to force regeneration
[ -z "$CLEAN_TESTS_OUT" ] && ((RANDOM % 2)) && CLEAN_TESTS_OUT=yes
if [ "$CLEAN_TESTS_OUT" = "yes" ]; then
	echo "Removing ./out"
	rm -rf ./out
fi

./examples.sh
if command -v dash >/dev/null; then
	dash ./scripts.sh
fi
if command -v bash >/dev/null; then
	bash ./scripts.sh
fi
if command -v busybox && busybox sh --help 2>/dev/null; then
	# note depending on busybox options (?) it's possible that
	# busybox sh will try to use its builtins over commands available
	# in path, but scripts require coreutils, so some commands will
	# fail (chown, chmod, realpath), but still work just enough to pass
	# tests...
	busybox sh ./scripts.sh
fi

. ./common.sh

build_check spaces "file test\ space.tar.zst"
build_check install_files \
	"file-tar *tmp_swupdate*.tar.zst zoo/test\ space zoo/test\ space.tar"

cp -f ../mkimage.conf mkimage-aes.conf
echo 'ENCRYPT_KEYFILE="swupdate.aes-key"' >> mkimage-aes.conf
../genkey.sh --aes --config mkimage-aes.conf
conf=mkimage-aes.conf build_check aes

build_check board "swdesc 'iot-g4-es1 = '"
build_check board_fail

build_check exec_quoting "swdesc 'touch /tmp/swupdate-test'"
build_check exec_readonly "swdesc 'podman run.*read-only.*touch.*/fail'"

rm -f zoo/hardlink zoo/hardlink2
echo foo > zoo/hardlink
ln zoo/hardlink zoo/hardlink2
build_check hardlink_order
[ "$(cpio -t < out/hardlink_order.swu)" = "sw-description
sw-description.sig
scripts.tar.zst
hardlink
swupdate_post.sh.zst" ] || error "cpio content was not in expected order: $(cpio -t < out/hardlink_order.swu)"

# install test
SWUPDATE="${SWUPDATE:-swupdate}"
if command -v "$SWUPDATE" > /dev/null; then
	# setup
	HWREV="${HWREV:-/etc/hwrevision}"
	if [ -w "$HWREV" ]; then
		echo "iot-g4-es1 at1" > "$HWREV"
	fi
	# tests/install_files
	rm -rf /tmp/swupdate-test /target/tmp/swupdate-test
	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./out/install_files.swu -v -k ../swupdate.pem \
		|| error "swupdate failed"
	ls /tmp/swupdate-test
	[ "$(cat "/tmp/swupdate-test/zoo/test space")" = "test content" ] \
		|| error "test space content does not match"
	[ "$(tar tf "/tmp/swupdate-test/zoo/test space.tar")" = "test space" ] \
		|| error "test space.tar content does not match"
	rm -rf /tmp/swupdate-test

	# tests/aes
	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./out/aes.swu -v -k ../swupdate.pem -K swupdate.aes-key \
		|| error "swupdate failed"
	ls /tmp/swupdate-test
	[ "$(cat "/tmp/swupdate-test/test space")" = "test content" ] \
		|| error "test space content does not match"
	[ "$(tar tf "/tmp/swupdate-test/test space.tar")" = "test space" ] \
		|| error "test space.tar content does not match"
	rm -rf /tmp/swupdate-test

	# tests/board
	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./out/board.swu -v -k ../swupdate.pem \
		|| error "swupdate failed"
	ls /tmp/swupdate-test
	[ "$(cat "/tmp/swupdate-test/test space")" = "test content" ] \
		|| error "test space content does not match"
	[ "$(tar tf "/tmp/swupdate-test/test space.tar")" = "test space" ] \
		|| error "test space.tar content does not match"
	rm -rf /tmp/swupdate-test

	# tests/board_fail -- incorrect board here
	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./out/board_fail.swu -v -k ../swupdate.pem \
		&& error "Should not have succeeded"
	rm -rf /tmp/swupdate-test

	# These tests require podman, /target existing and semi-populated
	if command -v podman > /dev/null && [ -e /target/bin/sh ] \
		&& mkdir -p /target/var/app/volumes /target/var/app/rollback/volumes; then
		# tests/exec_quoting
		mkdir /tmp/swupdate-test /target/tmp/swupdate-test
		"$SWUPDATE" -i ./out/exec_quoting.swu -v -k ../swupdate.pem \
			|| error "swupdate failed"
		ls "/tmp/swupdate-test/1 \\, \", ',"$'\n'"bar" /tmp/swupdate-test/2 /tmp/swupdate-test/3 \
			|| error "exec_nochroot did not create expected files"
		ls "/target/tmp/swupdate-test/1 \\, \", ',"$'\n'"bar" /target/tmp/swupdate-test/2  /target/tmp/swupdate-test/3 \
			|| error "exec  did not create expected files"
		rm -rf /tmp/swupdate-test /target/tmp/swupdate-test

		# tests/exec_readonly (failure test)
		"$SWUPDATE" -i ./out/exec_readonly.swu -v -k ../swupdate.pem \
			&& error "Should not have succeeded"
	fi
fi

# finish with a successful command to not keep last failed on purpose test result
true
