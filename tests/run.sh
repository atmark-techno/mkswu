#!/bin/bash

set -ex

cd "$(dirname "$0")"

# sometimes remove tests/out directory to force regeneration
[ -z "$CLEAN_TESTS_OUT" ] && ((RANDOM % 2)) && CLEAN_TESTS_OUT=yes
if [ "$CLEAN_TESTS_OUT" = "yes" ]; then
	echo "Removing ./out"
	rm -rf ./out
fi

"${MKSWU:-../mkswu}" --genkey --cn test --plain --noprompt

. ./common.sh
./examples.sh
./build_tests.sh

if command -v dash >/dev/null; then
	dash ./scripts.sh
fi
if command -v bash >/dev/null; then
	bash ./scripts.sh
fi
if command -v busybox \
    && busybox sh --help 2>/dev/null\
    && ! busybox sh -c 'chmod --help' 2>&1 | grep -qi busybox; then
	# note if busybox has been compiled with
	# CONFIG_FEATURE_PREFER_APPLETS=y (e.g. debian)
	# there is no easy way to make scripts use binaries
	# in path instead of applets, so skip...
	busybox sh ./scripts.sh
fi

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
	"$SWUPDATE" -i ./out/install_files.swu -v -k ../swupdate.pem \
		|| error "swupdate failed"
	ls /tmp/swupdate-test
	[ "$(cat "/tmp/swupdate-test/zoo/test space")" = "test content" ] \
		|| error "test space content does not match"
	[ "$(tar tf "/tmp/swupdate-test/zoo/test space.tar")" = "test space" ] \
		|| error "test space.tar content does not match"
	[ -e "/tmp/swupdate-test/autobase/test space" ] \
		|| error "auto basedir extraction failed"
	[ "$(cat "/tmp/swupdate-test/subdir/test space")" = "test content" ] \
		|| error "subdir extraction failed"
	[ "$(cat "/tmp/swupdate-test/subdir space/test space")" = "test content" ] \
		|| error "subdir extraction with space failed"
	rm -rf /tmp/swupdate-test

	# tests/aes
	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./out/aes.swu -v -k ../swupdate.pem -K out/swupdate.aes-key \
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
			|| error "exec did not create expected files"
		rm -rf /tmp/swupdate-test /target/tmp/swupdate-test

		# tests/swdesc_script quoting
		mkdir /target/tmp/swupdate-test
		"$SWUPDATE" -i ./out/swdesc_script.swu -v -k ../swupdate.pem \
			|| error "swupdate failed"
		[ "$(cat /target/tmp/swupdate-test/preserve)" = "# ## okay
line1
line2 with space and ! \ @" ] || error "updated content does not match (podman)"
		rm -rf /target/tmp/swupdate-test

		# tests/exec_readonly (failure test)
		"$SWUPDATE" -i ./out/exec_readonly.swu -v -k ../swupdate.pem \
			&& error "Should not have succeeded"
	fi

	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./out/swdesc_script_nochroot.swu -v -k ../swupdate.pem \
		|| error "swupdate failed"
	[ "$(cat /tmp/swupdate-test/preserve)" = "# ## okay
line1
line2 with space and ! \ @" ] || error "updated content does not match (nochroot)"
	rm -rf /tmp/swupdate-test

	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./out/two_scripts.swu -v -k ../swupdate.pem \
		|| error "swupdate failed"
	[ "$(cat /tmp/swupdate-test/echo)" = "one
two" ] || error "updated content does not match (two scripts)"
	rm -rf /tmp/swupdate-test
fi

# finish with a successful command to not keep last failed on purpose test result
true
