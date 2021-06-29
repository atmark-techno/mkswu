error() {
	echo "$@" >&2
	cleanup
	exit 1
}

umount_if_mountpoint() {
	local dir="$1"
	if ! awk '$5 == "'"$dir"'" { exit 1 }' < /proc/self/mountinfo; then
		umount "$dir" || error "Could not umount $dir"
	fi
}

cleanup() {
	umount_if_mountpoint /target/var/app/storage/overlay
	umount_if_mountpoint /target/var/app/storage
	umount_if_mountpoint /target/var/app/volumes
	umount_if_mountpoint /target/var/app/volumes_persistent
	umount_if_mountpoint /target/var/tmp
	umount_if_mountpoint /target
}

init_common() {
	if [ -e "$TMPDIR/sw-description" ]; then
		SWDESC="$TMPDIR/sw-description"
	elif [ -e "/tmp/sw-description" ]; then
		SWDESC="/tmp/sw-description"
	else
		error "sw-description not found!"
	fi

	# debug tests
	grep -q "ATMARK_SKIP_SCRIPTS" "$SWDESC" && exit 0
}

init_common
