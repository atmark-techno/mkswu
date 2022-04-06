probe_current() {
	rootdev=$(swupdate -g)

	[ "${rootdev#mmcblk}" = "$rootdev" ] || rootdev="/dev/$rootdev"
	[ -e "$rootdev" ] || rootdev="$(findfs "$rootdev")"
	[ -e "$rootdev" ] || error "Could not find what partition linux booted from to guess what to flash"

	if [ "${rootdev##*[a-z]}" = "1" ]; then
		ab=1
	else
		ab=0
	fi
	partdev="${rootdev%[0-9]}"
	rootdev="$partdev"
	[ "${partdev#/dev/mmcblk}" = "$partdev" ] \
		|| rootdev="${partdev%p}"
}

init_vars() {
	local debug
	# override from sw-description
	debug=$(awk '/DEBUG_FLASH_DEV/ { print $NF }' "$SWDESC")
	if [ -n "$debug" ]; then
		rootdev="$debug"
		partdev="$rootdev"
		[ "${partdev#/dev/mmcblk}" = "$partdev" ] \
			|| partdev="${rootdev}p"
	fi
	debug=$(awk '/DEBUG_FLASH_AB/ { print $NF }' "$SWDESC")
	[ -n "$debug" ] && ab="$debug"

	if [ -z "$rootdev" ] || [ -z "$ab" ]; then
		probe_current
	fi

	# non-fatal if not present
	board=$(awk '{print $1; exit}' /etc/hwrevision 2>/dev/null)
}

init_vars_update() {
	if needs_update base_os; then
		update_rootfs=baseos
	elif needs_update_regex "extra_os.*" \
	    || grep -q "CONTAINER_CLEAR" "$SWDESC"; then
		update_rootfs=1
	fi
	if update_rootfs || needs_update boot \
	    || ! grep -q "POSTACT_CONTAINER" "$SWDESC"; then
		needs_reboot=1
	fi
}

save_vars() {
	printf "%s\n" "$rootdev" > "$SCRIPTSDIR/rootdev" \
		&& printf "%s\n" "$ab" > "$SCRIPTSDIR/ab" \
		|| error "Could not save local variables"
	if needs_reboot; then
		touch "$SCRIPTSDIR/needs_reboot" \
			|| error "Could not save need to reboot variable"
	fi
	if update_rootfs; then
		echo "$update_rootfs" > "$SCRIPTSDIR/update_rootfs" \
			|| error "Could not save rootfs update variable"
	fi
}

fail_redundant_update() {
	# if no version changed, clean up and fail script to avoid
	# downloading the rest of the image
	if ! grep -q "#FORCE_VERSION" "$SWDESC"; then
		if cmp -s /etc/sw-versions "$SCRIPTSDIR/sw-versions.merged"; then
			rm -rf "$SCRIPTSDIR"
			error "Nothing to do -- failing on purpose to save bandwidth"
		fi
		# also check B-side unless SW_ALLOW_ROLLBACK is set
		if [ -z "$SW_ALLOW_ROLLBACK" ] \
		    && mount "${partdev}$((ab+1))" /target 2>/dev/null; then
			if cmp -s /target/etc/sw-versions \
					"$SCRIPTSDIR/sw-versions.merged"; then
				rm -rf "$SCRIPTSDIR"
				error "Update looks like it already had been installed but rolled back, failing on purpose." \
					"Set SW_ALLOW_ROLLBACK=1 environment variable to force installing anyway."
			fi
			umount /target
		fi
	fi
}

init() {
	lock_update
	cleanup

	init_vars
	gen_newversion
	init_vars_update

	fail_redundant_update
	printf "Using %s on boot %s. Reboot%s required.\n" "$rootdev" "$ab" \
		"$(needs_reboot || echo " not")"

	save_vars
}

init
