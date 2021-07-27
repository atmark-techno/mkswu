cleanup_uboot() {
	local dev

	if dev=$(readlink -e /dev/swupdate_ubootdev) && [ "${dev#/dev/loop}" != "$dev" ]; then
		losetup -d "$dev" >/dev/null 2>&1
	fi
	rm -f /dev/swupdate_ubootdev

	if ! needs_reboot; then
		return
	fi

	if [ "$rootdev" = "/dev/mmcblk2" ]; then
		mmc bootpart enable "$((ab+1))" 0 "$rootdev" \
			|| error "Could not flip mmc boot flag"
	elif [ -s /etc/fw_env.config ]; then
		# if uboot env is supported, use it (e.g. sd card)
		fw_setenv mmcpart $((ab+1))
	else
		# assume gpt boot e.g. extlinux
		sgdisk --attributes=$((ab+1)):set:2 --attributes=$((!ab+1)):clear:2 "$rootdev"
	fi
}

cleanup_uboot
