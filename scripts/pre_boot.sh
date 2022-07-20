copy_boot() {
	local target="$1" version="$2"
	local other_vers cur_vers
	local flash_dev cur_dev

	# skip for sd cards
	[ -e "${rootdev}boot1" ] || return

	other_vers=$(get_version "other_$version" old)
	cur_vers=$(get_version "$version" old)

	[ "$other_vers" = "$cur_vers" ] && return

	echo "Copying boot over from existing"
	flash_dev="${rootdev#/dev/}boot${ab}"
	cur_dev="${rootdev}boot$((!ab))"
	if ! echo 0 > "/sys/block/$flash_dev/force_ro" \
	    || ! copy_boot_"$target"; then
		echo 1 > "/sys/block/$flash_dev/force_ro"
		error "Could not copy $target over"
	fi
	echo 1 > "/sys/block/$flash_dev/force_ro"
}

copy_boot_imxboot() {
	dd if="$cur_dev" of="/dev/$flash_dev" bs=1M count=4 \
			conv=fdatasync status=none \
		|| return

	# ... and make sure we reset env
	dd if=/dev/zero of="/dev/$flash_dev" bs=8k count=3 \
			seek=$((0x3fa000)) oflag=seek_bytes \
			conv=fdatasync status=none \
		|| return
	# optionally restore user env if any
	# this is before install so use current /boot/uboot_env --
	# updating these files only impact new uboot updates!
	if stat /boot/uboot_env.d/* > /dev/null 2>&1; then
		cat /boot/uboot_env.d/* > "$SCRIPTSDIR/default_env" \
			|| error "uboot env files existed but could not merge them"
		sed -e "s:${rootdev}boot[0-1]:/dev/$flash_dev:" \
				/etc/fw_env.config > "$SCRIPTSDIR/fw_env.config" \
			|| error "Could not generate copy fw_env.config"
		fw_setenv_quiet --config "$SCRIPTSDIR/fw_env.config" \
				--defenv "$SCRIPTSDIR/default_env" \
			|| error "Could not restore default env"
		rm -f "$SCRIPTSDIR/fw_env.config" "$SCRIPTSDIR/default_env"
	fi
}
copy_boot_linux() {
	dd if="$cur_dev" of="/dev/$flash_dev" bs=1M skip=5 seek=5 \
			conv=fdatasync status=none
}

prepare_boot() {
	local dev
	local setup_link=""

	if needs_update "boot_linux"; then
		setup_link=1
	else
		copy_boot linux boot_linux
	fi
	if needs_update "boot"; then
		setup_link=1
	else
		copy_boot imxboot boot
	fi
	[ -z "$setup_link" ] && return

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
