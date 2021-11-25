post_success_hawkbit() {
	local dev="${partdev}5"
	local basemount newstate

	# hawkbit service requires transmitting install status on next
	# restart, so keep track of it in appfs

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

post_success_usb() {
	# if the image is a force install image, move it to avoid install loop
	# we don't need to do this if the post action is poweroff
	if grep -q FORCE_VERSION "$SWDESC" \
	    && ! grep -q POSTACT_POWEROFF "$SWDESC"; then
		mv -v "$SWUPDATE_USB_SWU" "$SWUPDATE_USB_SWU.installed"
	fi
}

post_success() {
	[ -n "$SWUPDATE_HAWKBIT" ] && post_success_hawkbit
	[ -n "$SWUPDATE_USB_SWU" ] && post_success_usb
}

post_success
