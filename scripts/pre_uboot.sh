copy_uboot() {
	local other_vers cur_vers
	local flash_dev cur_dev

	other_vers=$(get_version other_uboot /etc/sw-versions)
	cur_vers=$(get_version uboot /etc/sw-versions)

	[ "$other_vers" = "$cur_vers" ] && return

	flash_dev="${mmcblk#/dev/}boot${ab}"
	cur_dev="${mmcblk}boot$((!ab))"
	if ! echo 0 > /sys/block/$flash_dev/force_ro \
		|| ! dd if="$cur_dev" of="/dev/$flash_dev" bs=1M count=3 status=none \
		|| ! dd if=/dev/zero of="/dev/$flash_dev" bs=1M seek=3 count=1 status=none; then
		echo 1 > /sys/block/$flash_dev/force_ro
		error "Could not copy uboot over"
	fi
	echo 1 > /sys/block/$flash_dev/force_ro
}

prepare_uboot() {
	local dev
	# cleanup any leftovers first
	if dev=$(readlink -e /dev/swupdate_ubootdev) && [ "${dev#/dev/loop}" != "$dev" ]; then
		losetup -d "$dev" >/dev/null 2>&1
	fi
	rm -f /dev/swupdate_ubootdev

	if ! needs_update "uboot"; then
		copy_uboot
		return
	fi

	if [ -e "${mmcblk}boot${ab}" ]; then
		ln -s "${mmcblk}boot${ab}" /dev/swupdate_ubootdev \
			|| error "failed to create link"
	else
		# probably sd card: prepare a loop device 32k into sd card
		# so swupdate can write directly
		# XXX racy
		ln -s "$(losetup -f)" /dev/swupdate_ubootdev \
			|| error "failed to create link"
		losetup -o $((32*1024)) -f "$mmcblk" \
			|| error "failed to setup loop device"
	fi
}

prepare_uboot
