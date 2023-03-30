#!/bin/bash

set -e

TESTS_DIR=$(dirname "${BASH_SOURCE[0]}")
MKSWU=$(command -v "${MKSWU:-$TESTS_DIR/../mkswu}") \
	|| error "mkswu script not found"
SCRIPTS_DIR="$TESTS_DIR/../scripts"
# tests assume no encryption unless forced
export MKSWU_ENCRYPT_KEYFILE=""
if [ "${MKSWU%/usr/bin/mkswu}" != "$MKSWU" ]; then
	SCRIPTS_DIR="${MKSWU%/bin/mkswu}/share/mkswu/scripts"
fi
. "${SCRIPTS_DIR}/versions.sh"

error() {
	printf "%s\n" "$@" >&2
	exit 1
}

export SWDESC_TEST=1

check() {
	local type="$1"
	local file tar regex board=""
	local component version real_version
	shift
	case "$type" in
	file)
		[ $# -gt 0 ] || error "file check has no argument"
		for file; do
			cpio --quiet -t < "$swu"| grep -qx "$file" ||
				error "$file not in swu"
		done
		;;
	file-tar)
		[ $# -gt 1 ] || error "file-tar needs tar and content args"
		tar="$1"
		shift
		tar -t --wildcards -f "$dir/"$tar "$@" > /dev/null || error "Missing files in $tar"
		;;
	version)
		[ $# -ge 2 ] && [ $1 = "--board" ] && board=$2 && shift 2
		[ $# -eq 2 ] || error "version usage: <component> [--board <board>] <version regex>"
		component="$1"
		version="$2"

		## from scripts/version.sh gen_newversion:
		extract_swdesc_versions < "$dir/sw-description" \
			> "$dir/sw-versions.present"
		real_version=$(SCRIPTSDIR="$dir" get_version --install-if "$component" present)

		[[ "$real_version" =~ ^$version$ ]] ||
			error "Version $component expected $version got $real_version"
		;;
	swdesc)
		[ $# -gt 0 ] || error "swdesc check needs argument"
		for regex; do
			grep -q -E "$regex" "$dir/sw-description" \
				|| error "$regex not found in $dir/sw-description"
		done
		;;
	*) error "Unknown check type: $type" ;;
	esac
}

build_check() {
	local mkswu_arg=()
	local name="${name:-${1##*/}}"
	name="${name%.desc}"
	local dir="$TESTS_DIR/out/.$name"
	local swu="$TESTS_DIR/out/$name.swu"
	local check

	while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
		if [ "$1" = "---" ]; then
			mkswu_arg+=( -- )
		else
			mkswu_arg+=( "$1" )
		fi
		shift
	done
	[ "$1" = "--" ] && shift

	echo "Building $name"
	"$MKSWU" -o "$swu" "${mkswu_arg[@]}" \
		|| error "mkswu failed for $name"

	for check; do
		eval check "$check"
	done
}

build_fail() {
	local name="${name:-${1##*/}}"
	name="${name%.desc}"
	local dir="$TESTS_DIR/out/.$name"
	local swu="$TESTS_DIR/out/$name.swu"
	local check

	echo "Building $name (must fail)"
	! "$MKSWU" -o "$swu" "$@"
}
