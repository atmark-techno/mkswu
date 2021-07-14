#!/bin/bash

set -ex
./tests/examples.sh

. ./tests/common.sh

build_check tests/spaces "file container_docker_io_tag_with_spaces.pull"
build_check tests/install_files "file-tar somefiles.tar.zst test\ space test\ space.tar"

# install test
SWUPDATE="${SWUPDATE:-swupdate}"
if command -v "$SWUPDATE" > /dev/null; then
	rm -rf /tmp/swupdate-test
	mkdir /tmp/swupdate-test
	"$SWUPDATE" -i ./tests/out/install_files.swu -v -k swupdate.pem
	ls /tmp/swupdate-test
	[ -e "/tmp/swupdate-test/test space" ] || error "Not installed properly"
	[ -e "/tmp/swupdate-test/test space.tar" ] || error "Not installed properly"
	rm -rf /tmp/swupdate-test
fi
