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
		mv -v "$SWUPDATE_USB_SWU" "$SWUPDATE_USB_SWU.installed" \
			|| echo "Could not rename force version usb install image, might have a reinstall loop" >&2
	fi
}

set_fw_update_ind() {
	local led_dir=/sys/class/leds/FW_UPDATE_IND

	[ -e "$led_dir/brightness" ] || return

	# It's too late to fail, but try to warn if we couldn't set led
	cat "$led_dir/max_brightness" > "$led_dir/brightness" \
		|| echo "Could not set FW_UPDATE_IND" >&2
}


post_success() {
	[ -n "$SWUPDATE_HAWKBIT" ] && post_success_hawkbit
	[ -n "$SWUPDATE_USB_SWU" ] && post_success_usb
	set_fw_update_ind
}

post_success
