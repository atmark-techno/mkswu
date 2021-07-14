#!/bin/bash

set -ex
./tests/examples.sh

. ./tests/common.sh

build_check tests/spaces "file container_docker_io_tag_with_spaces.pull"
build_check tests/install_files "file-tar somefiles.tar.zst test\ space test\ space.tar"

sed -e "s/# ENCRYPT_KEYFILE/ENCRYPT_KEYFILE/" mkimage.conf > tests/mkimage-aes.conf
./genkey.sh --aes --config tests/mkimage-aes.conf
conf=tests/mkimage-aes.conf build_check tests/aes

# install test
SWUPDATE="${SWUPDATE:-swupdate}"
HWREV="${HWREV:-/etc/hwrevision}"
if command -v "$SWUPDATE" > /dev/null; then
	# setup
	if [ "$(id -u)" = "0" ] || [ -w "$HWREV" ]; then
		echo "armadillo yakushima-1.0" > "$HWREV"
	fi
	# tests/install_files
	rm -rf /tmp/swupdate-test
	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./tests/out/install_files.swu -v -k swupdate.pem
	ls /tmp/swupdate-test
	[ "$(cat "/tmp/swupdate-test/test space")" = "test content" ] \
		|| error "test space content does not match"
	[ "$(tar tf "/tmp/swupdate-test/test space.tar")" = "test space" ] \
		|| error "test space.tar content does not match"
	rm -rf /tmp/swupdate-test

	# tests/aes
	rm -rf /tmp/swupdate-test
	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./tests/out/aes.swu -v -k swupdate.pem -K swupdate.aes-key
	ls /tmp/swupdate-test
	[ "$(cat "/tmp/swupdate-test/test space")" = "test content" ] \
		|| error "test space content does not match"
	[ "$(tar tf "/tmp/swupdate-test/test space.tar")" = "test space" ] \
		|| error "test space.tar content does not match"
	rm -rf /tmp/swupdate-test
fi
