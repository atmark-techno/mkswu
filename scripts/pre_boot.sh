copy_boot() {
	local target="$1" version="$2"
	local other_vers cur_vers
	local flash_dev cur_dev

	# skip for sd cards / qemu
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
	local env_offset env_sz

	# We copy until env and clear env.
	# This assumes nothing is present between redundant envs
	env_offset=$(awk '/^[^#]/ && $2 > 0 {
			if (!start || $2 < start)
				start = $2;
			if (!end || $2 + $3 > end)
				end = $2 + $3;
		}
		END {
			if (!start) exit(1);
			printf("%d,%d\n", start, end-start);
		}
		' < /etc/fw_env.config) \
		|| error "Could not get boot env location"
	env_sz="${env_offset##*,}"
	env_offset="${env_offset%,*}"

	dd if="$cur_dev" of="/dev/$flash_dev" bs="$env_offset" count=1 \
			conv=fdatasync status=none \
		|| return
	dd if=/dev/zero of="/dev/$flash_dev" bs="$env_sz" count=1 \
			seek="$env_offset" oflag=seek_bytes \
			conv=fdatasync status=none \
		|| return
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
