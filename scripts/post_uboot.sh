cleanup_uboot() {
	local dev

	if dev=$(readlink -e /dev/swupdate_ubootdev) && [ "${dev#/dev/loop}" != "$dev" ]; then
		losetup -d "$dev" >/dev/null 2>&1
	fi 
	rm -f /dev/swupdate_ubootdev

	if ! needs_reboot; then
		return
	fi

	if [ "$mmcblk" = "/dev/mmcblk2" ]; then 
		mmc bootpart enable "$((ab+1))" 0 "$mmcblk" \
			|| error "Could not flip mmc boot flag"
	fi
}

cleanup_uboot