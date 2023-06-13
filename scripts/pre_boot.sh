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
	if cmp -s -n "$env_offset" "$cur_dev" "/dev/$flash_dev"; then
		echo "boot already up to date"
		return
	fi

	echo "Copying boot to $flash_dev"
	bootdev_unlock
	dd if="$cur_dev" of="/dev/$flash_dev" bs="$env_offset" count=1 \
			conv=fdatasync status=none \
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
			conv=fdatasync status=none || return
	bootdev_lock
}

prepare_boot() {
	local dev
	local setup_link=""

	if needs_update "boot_linux"; then
		setup_link=1
	elif [ -n "$(get_version boot_linux)" ]; then
		# only copy if boot_linux exists
		copy_boot linux
	fi
	if needs_update "boot"; then
		setup_link=1
		touch "$SCRIPTSDIR/boot_updated"
	else
		copy_boot boot
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
