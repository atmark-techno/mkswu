cleanup_boot() {
	local dev

	if dev=$(readlink -e /dev/swupdate_bootdev) && [ "${dev#/dev/loop}" != "$dev" ]; then
		losetup -d "$dev" >/dev/null 2>&1
	fi
	rm -f /dev/swupdate_bootdev

	if ! needs_reboot; then
		return
	fi

	if [ "$rootdev" = "/dev/mmcblk2" ]; then
		mmc bootpart enable "$((ab+1))" 0 "$rootdev" \
			|| error "Could not flip mmc boot flag"
	elif [ -s /etc/fw_env.config ]; then
		# if uboot env is supported, use it (e.g. sd card)
		fw_setenv mmcpart $((ab+1)) \
			|| error " Could not setenv mmcpart"
	elif [ -e /target/boot/extlinux.conf ]; then
		# assume gpt boot e.g. extlinux
		sgdisk --attributes=$((ab+1)):set:2 --attributes=$((!ab+1)):clear:2 "$rootdev" \
			|| error "Could not set boot attribute"

		sed -i -e "s/root=[^ ]*/root=LABEL=rootfs_${ab}/" /target/boot/extlinux.conf \
			|| error "Could not update extlinux.conf"
		extlinux -i /target/boot || error "Could not reinstall bootloader"
	else
		error "Do not know how to A/B switch this system"
	fi

	# from here on, failure is not appropriate
	soft_fail=1
}

cleanup_boot
