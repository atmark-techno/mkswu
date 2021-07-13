#!/bin/bash

set -e

. scripts/versions.sh

error() {
	echo "$@" >&2
	exit 1
}

check() {
	local type="$1"
	local file tar
	local component version real_version
	shift
	case "$type" in
	file)
		[ $# -gt 0 ] || error "file check has no argument"
		for file; do
			cpio -t < "$name".swu | grep -qx "$file" ||
				error "$file not in swu"
		done
		;;
	file-tar)
		[ $# -gt 1 ] || error "file-tar needs tar and content args"
		tar="$1"
		shift
		tar tf "$name/$tar" "$@" > /dev/null || error "Missing files in $tar"
		;;
	version)
		[ $# -eq 2 ] || error "version usage: <component> <version regex>"
		component="$1"
		version="$2"

		## from scripts/version.sh gen_newversion:
		parse_swdesc < "$name/sw-description" > "$name/sw-versions.present"
		real_version=$(get_version "$component" "$name/sw-versions.present")

		[[ "$real_version" =~ $version ]] ||
			error "Version $component expected $version got $real_version"
		;;
	*) error "Unknown check type: $type" ;;
	esac
}

build_check() {
	local conf="$1"
	local name="${conf##*/}"
	local name="tests/out/$name"
	local check
	shift

	echo "Building $name"
	./mkimage.sh -o "$name.swu" "$conf.conf"

	for check; do
		check $check
	done
}
