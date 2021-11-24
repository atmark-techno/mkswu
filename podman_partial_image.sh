#!/bin/sh

# SC2039: local is ok for dash and busybox ash
# shellcheck disable=SC2039

error() {
	printf "%s\n" "$@" >&2
	exit 1
}

usage() {
	echo "Usage: $0 [-b base [-b base...]] [-o out.tar] archive [archive..]"
	echo "base = image name recognizable by podman image inspect, to be removed from archive"
	echo "archive = image name recognizable by podman save"
}

inspect_image() {
	local image="$1"

	podman inspect --format "{{.RootFS.Layers}}" "$image" |
		sed -e 's/^\[\|\]$//g' -e 's/\<sha256://g' -e 's/ /\n/g' >> "$tmpdir/known_hashs"
}

trim_archives() {
	local hash tar_options="" file

	podman save -m --format=docker-archive "$@" | tar -C "$tmpdir/archive" -x || error "Could not extract images: $*"

	while read -r hash; do
		file="$tmpdir/archive/$hash.tar"
		[ -e "$file" ] || continue
		# podman verifies the archive contains a tar for all layers even if they're not used
		rm -f "$file" && touch -d "@0" "$file" && chmod 444 "$file" || error "Could not truncate layer in archive"
	done < "$tmpdir/known_hashs"

	if [ -n "$RENAME" ]; then
		sed -i $RENAME "$tmpdir/archive/manifest.json" "$tmpdir/archive/repositories"
	fi

	# podman generates archives in which owner is set to root,
	# busybox tar doesn't allow that so only add option for GNU tar
	if tar --version | grep -q GNU; then
		tar_options="--owner root --group root --numeric-owner"
	fi

	( cd "$tmpdir/archive"; tar ${tar_options} -c [0-9a-z]*; ) > "$OUTPUT" \
		|| error "Could not create new archive"
}

main() {
	local OUTPUT=image.tar
	local RENAME
	local tmpdir

	tmpdir=$(mktemp -d -t make_partial_image.XXXXXX) || error "Could not create temp dir"
	trap "rm -rf \"$tmpdir\"" EXIT
	mkdir "$tmpdir/archive"
	touch "$tmpdir/known_hashs"

	while [ $# -gt 0 ]; do
		case "$1" in
		-b|--base)
			[ $# -ge 2 ] || error "Missing argument to $1"
			inspect_image "$2"
			shift 2
			;;
		-o|--output)
			[ $# -ge 2 ] || error "Missing argument to $1"
			OUTPUT="$2"
			shift 2
			;;
		-R|--rename)
			[ $# -ge 2 ] || error "Missing argument to $1"
			RENAME="$RENAME -e $2"
			shift 2
			;;

		-h|--help)
			usage
			exit 0
			;;
		--)
			shift
			break
			;;
		-*)
			error "Invalid argument $1"
			;;
		*)
			break
			;;
		esac
	done
	
	[ $# -lt 1 ] && usage && exit 1

	trim_archives "$@"
}

main "$@"
