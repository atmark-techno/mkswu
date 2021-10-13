#!/bin/bash

set -ex

# sometimes remove tests/out directory to force regeneration
[ -z "$CLEAN_TESTS_OUT" ] && ((RANDOM % 2)) && CLEAN_TESTS_OUT=yes
if [ "$CLEAN_TESTS_OUT" = "yes" ]; then
	echo "Removing ./tests/out"
	rm -rf ./tests/out
fi

./tests/examples.sh
./tests/scripts.sh

. ./tests/common.sh

build_check tests/spaces "file test\ space.tar.zst"
build_check tests/install_files \
	"file-tar tests__tmp_swupdate_..e_zoo_test_space_tar_e1a4910d4523d9256c895c530987e9c2ca267063.tar.zst zoo/test\ space zoo/test\ space.tar"

sed -e "s/# ENCRYPT_KEYFILE/ENCRYPT_KEYFILE/" mkimage.conf > tests/mkimage-aes.conf
./genkey.sh --aes --config tests/mkimage-aes.conf
conf=tests/mkimage-aes.conf build_check tests/aes

build_check tests/board "swdesc 'yakushima-es1 = '"
build_check tests/board_fail

build_check tests/exec_quoting "swdesc 'touch /tmp/swupdate-test'"
build_check tests/exec_readonly "swdesc 'podman run.*read-only.*touch.*/fail'"

# install test
SWUPDATE="${SWUPDATE:-swupdate}"
HWREV="${HWREV:-/etc/hwrevision}"
if command -v "$SWUPDATE" > /dev/null; then
	# setup
	if [ "$(id -u)" = "0" ] || [ -w "$HWREV" ]; then
		echo "yakushima-es1 at1" > "$HWREV"
	fi
	# tests/install_files
	rm -rf /tmp/swupdate-test /target/tmp/swupdate-test
	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./tests/out/install_files.swu -v -k swupdate.pem \
		|| error "swupdate failed"
	ls /tmp/swupdate-test
	[ "$(cat "/tmp/swupdate-test/zoo/test space")" = "test content" ] \
		|| error "test space content does not match"
	[ "$(tar tf "/tmp/swupdate-test/zoo/test space.tar")" = "test space" ] \
		|| error "test space.tar content does not match"
	rm -rf /tmp/swupdate-test

	# tests/aes
	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./tests/out/aes.swu -v -k swupdate.pem -K swupdate.aes-key \
		|| error "swupdate failed"
	ls /tmp/swupdate-test
	[ "$(cat "/tmp/swupdate-test/test space")" = "test content" ] \
		|| error "test space content does not match"
	[ "$(tar tf "/tmp/swupdate-test/test space.tar")" = "test space" ] \
		|| error "test space.tar content does not match"
	rm -rf /tmp/swupdate-test

	# tests/board
	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./tests/out/board.swu -v -k swupdate.pem \
		|| error "swupdate failed"
	ls /tmp/swupdate-test
	[ "$(cat "/tmp/swupdate-test/test space")" = "test content" ] \
		|| error "test space content does not match"
	[ "$(tar tf "/tmp/swupdate-test/test space.tar")" = "test space" ] \
		|| error "test space.tar content does not match"
	rm -rf /tmp/swupdate-test

	# tests/board_fail -- incorrect board here
	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./tests/out/board_fail.swu -v -k swupdate.pem \
		&& error "Should not have succeeded"
	rm -rf /tmp/swupdate-test

	# These tests require /target existing and semi-populated
	if [ -e /target/bin/sh ] \
		&& mkdir -p /target/var/app/volumes /target/var/app/rollback/volumes; then
		# tests/exec_quoting
		mkdir /tmp/swupdate-test /target/tmp/swupdate-test
		"$SWUPDATE" -i ./tests/out/exec_quoting.swu -v -k swupdate.pem \
			|| error "swupdate failed"
		ls "/tmp/swupdate-test/1 \\, \", ',"$'\n'"bar" /tmp/swupdate-test/2 /tmp/swupdate-test/3 \
			|| error "exec_nochroot did not create expected files"
		ls "/target/tmp/swupdate-test/1 \\, \", ',"$'\n'"bar" /target/tmp/swupdate-test/2  /target/tmp/swupdate-test/3 \
			|| error "exec  did not create expected files"
		rm -rf /tmp/swupdate-test /target/tmp/swupdate-test

		# tests/exec_readonly (failure test)
		"$SWUPDATE" -i ./tests/out/exec_readonly.swu -v -k swupdate.pem \
			&& error "Should not have succeeded"
	fi
fi

# finish with a successful command to not keep last failed on purpose test result
true
