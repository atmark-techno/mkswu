post_success() {
	local dev="${partdev}5"
	local basemount newstate

	# only create the file for hawkbit service, which sets this env var
	[ -n "$SWUPDATE_HAWKBIT" ] || return

	basemount=$(mktemp -d -t btrfs-swupdate.XXXXXX) || error "Could not create temp dir"
	if ! mount -t btrfs -o subvol=/swupdate "$dev" "$basemount" 2>/dev/null; then
		mount -o subvol=/ "$dev" "$basemount" || error "Could not mount app root"
		btrfs subvolume create "$basemount/swupdate" || error "Could not create swupdate subvolume"
		umount "$basemount" || error "Could not umount app root"
		mount -o subvol=/swupdate "$dev" "$basemount" || error "Could not mount swupdate subvolume"
	fi

	if needs_reboot; then
		newstate="${partdev}$((ab+1))"
	else
		newstate="${partdev}$((!ab+1))"
	fi

	echo "$newstate" > "$basemount/updated-rootfs" || error "Could not write success file"
	umount "$basemount" || error "Could not umount swupdate subvolume"
	rmdir "$basemount"
}

post_success
