copy_boot() {
	local other_vers cur_vers
	local flash_dev cur_dev

	other_vers=$(get_version other_boot /etc/sw-versions)
	cur_vers=$(get_version boot /etc/sw-versions)

	[ "$other_vers" = "$cur_vers" ] && return

	# skip for sd cards
	[ -e "${rootdev}boot1" ] || return


	echo "Copying boot over from existing"
	flash_dev="${rootdev#/dev/}boot${ab}"
	cur_dev="${rootdev}boot$((!ab))"
	if ! echo 0 > "/sys/block/$flash_dev/force_ro" \
		|| ! dd if="$cur_dev" of="/dev/$flash_dev" bs=1M count=3 conv=fdatasync status=none \
		|| ! dd if=/dev/zero of="/dev/$flash_dev" bs=1M seek=3 count=1 conv=fdatasync status=none; then
		echo 1 > "/sys/block/$flash_dev/force_ro"
		error "Could not copy boot over"
	fi
	echo 1 > "/sys/block/$flash_dev/force_ro"
}

prepare_boot() {
	local dev

	if ! needs_update "boot"; then
		copy_boot
		return
	fi

	if [ -e "${rootdev}boot${ab}" ]; then
		ln -s "${rootdev}boot${ab}" /dev/swupdate_bootdev \
			|| error "failed to create link"
	else
		# probably sd card: prepare a loop device 32k into sd card
		# so swupdate can write directly
		losetup -o $((32*1024)) -f "$rootdev" \
			|| error "failed to setup loop device"
		dev=$(losetup -a | awk -F : "/${rootdev##*/}/ && /$((32*1024))/ { print \$1 }")
		ln -s "$dev" /dev/swupdate_bootdev \
			|| error "failed to create link"
	fi
}

prepare_boot
