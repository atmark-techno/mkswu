#!/bin/bash

set -e

cd "$(dirname "$0")"/..

rm -rf tests/out/install
DESTDIR="$PWD/tests/out/install" \
	make install_mkswu install_examples

# Makefile install_examples
excludes=(
	-path './.*' -prune -o
	-path './armadillo*/.*' -prune -o
	-name '*.swu' -prune -o
	-name 'kernel' -prune -o
	-name 'Image.signed' -prune -o
	-name 'imx-boot*' -prune -o
	-name "*.dek_offsets" -prune -o
	-name "baseos*.tar.zst" -prune -o
	-name "*.tar" -prune -o
	-name "*.apk" -prune -o
)
diff -u <(cd examples && find . "${excludes[@]}" -print  | sort) \
	<(cd tests/out/install/usr/share/mkswu/examples && find . | sort)

# Makefile `install_scripts`
diff -u <(cd scripts && find . -not -name '.*' | sort) \
	<(cd tests/out/install/usr/share/mkswu/scripts && find . -mindepth 1 | sort)
