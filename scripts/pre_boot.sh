bootdev_lock() {
	[ -e "/sys/block/$flash_dev/force_ro" ] || return 0

	echo 1 > "/sys/block/$flash_dev/force_ro" \
		|| warning "Could not make $flash_dev ro again"
}

bootdev_unlock() {
	[ -e "/sys/block/$flash_dev/force_ro" ] || return 0

	echo 0 > "/sys/block/$flash_dev/force_ro" \
		|| error "Could not make $flash_dev read-write"
}

copy_boot() {
	local target="$1"
	local flash_dev cur_dev

	# skip for sd cards / qemu
	[ -e "${rootdev}boot1" ] || return

	flash_dev="${rootdev#/dev/}boot${ab}"
	cur_dev="${rootdev}boot$((!ab))"

	if ! copy_boot_"$target"; then
		bootdev_lock
		error "Could not copy $target to $flash_dev"
	fi
}

copy_boot_boot() {
	local env_offset

	# We copy until env start if changed.
	# Env will be cleared in post_boot
	env_offset=$(awk '/^[^#]/ && $2 > 0 {
			if (!start || $2 < start)
				start = $2;
		}
		END {
			if (!start) exit(1);
			printf("%d\n", start);
		}
		' < /etc/fw_env.config) \
		|| error "Could not get boot env location"

	# already up to date?
	if cmp -s -n "$env_offset" "$cur_dev" "/dev/$flash_dev" 2>/dev/null; then
		echo "boot already up to date"
		return
	fi

	echo "Copying boot to $flash_dev"
	bootdev_unlock
	dd if="$cur_dev" of="/dev/$flash_dev" bs="$env_offset" count=1 \
			conv=fsync status=none \
		|| return
	bootdev_lock
}

copy_boot_linux() {
	local offset=$((5*1024*1024))

	if cmp -s "$cur_dev" "/dev/$flash_dev" "$offset" "$offset"; then
		echo "boot_linux already up to date"
		return
	fi

	echo "Copying boot_linux to $flash_dev"
	bootdev_unlock
	dd if="$cur_dev" of="/dev/$flash_dev" bs=1M skip=5 seek=5 \
			conv=fsync status=none || return
	bootdev_lock
}

workaround_ax2_mmc() {
	# older firmware for Armadillo X2/IoT G4 can brick the MMC if power is lost
	# while writing to boot partitions with >= 16KB blocks:
	# limit to 8KB if required.
	[ "$(get_mmc_name)" = G1M15L ] || return
	# affected version: ECQT00HS
	[ "$(cat "/sys/class/block/${rootdev#/dev/}/device/fwrev")" = 0x4543515430304853 ] || return

	echo 8 > "/sys/class/block/${rootdev#/dev/}boot0/queue/max_sectors_kb"
	echo 8 > "/sys/class/block/${rootdev#/dev/}boot1/queue/max_sectors_kb"
}

prepare_boot() {
	local setup_link=""

	# make sure we didn't leave a bootdev behind from previous update
	rm -f /dev/swupdate_bootdev

	workaround_ax2_mmc

	if needs_update "boot_linux"; then
		setup_link=1
	elif [ -n "$(get_version boot_linux)" ]; then
		# only copy if boot_linux exists
		copy_boot linux
	fi
	if needs_update "boot"; then
		setup_link=1
		touch "$MKSWU_TMP/boot_updated"
	else
		copy_boot boot
	fi
	[ -z "$setup_link" ] && return

	# for eMMC just link to the right side, swupdate will write it out
	if [ -e "${rootdev}boot${ab}" ]; then
		ln -s "${rootdev}boot${ab}" /dev/swupdate_bootdev \
			|| error "failed to create boot image link"
		return
	fi

	case "$rootdev" in
	/dev/mmcblk*) ;;
	*) error "Cannot write boot image on $rootdev";;
	esac

	# probably a SD card:
	# save boot image to a temporary file which will be written
	# at proper offset in post boot.
	touch /dev/swupdate_bootdev \
		|| error "failed to create boot image temporary file"
}

prepare_boot
