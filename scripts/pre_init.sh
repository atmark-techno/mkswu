probe_current() {
	local rootdev

	rootdev=$(sed -ne 's/.*root=\([^ ]*\).*/\1/p' < /proc/cmdline)

	case "$rootdev" in
	/dev/mmcblk*p*)
		mmcblk="${rootdev%p*}"
		if [ "${rootdev##*p}" = "1" ]; then
			ab=1
		else
			ab=0
		fi
		;;
	*) 
		error "Could not find what partition linux booted from to guess what to flash"
		;;
	esac
}

init_vars() {
	# override from sw-description
	rootdev=$(awk '/ATMARK_FLASH_DEV/ { print $NF }' "$SWDESC")
	[ -n "$rootdev" ] && mmcblk="$rootdev"
	rootdev=$(awk '/ATMARK_FLASH_AB/ { print $NF }' "$SWDESC")
	[ -n "$rootdev" ] && ab="$rootdev"

	if [ -z "$mmcblk" ] || [ -z "$ab" ]; then
		probe_current
	fi

	if needs_update uboot || needs_update base_os || needs_update kernel || needs_update extra_os; then
		needs_reboot=1
	fi
	printf "Using %s on boot %s. Reboot%s required.\n" "$mmcblk" "$ab" \
		"$(needs_reboot || echo " not")"
}

save_vars() {
	echo "$mmcblk" > "$SCRIPTSDIR/mmcblk" \
		&& echo "$ab" > "$SCRIPTSDIR/ab" \
		|| error "Could not save local variables"
	if needs_reboot; then
		touch "$SCRIPTSDIR/needs_reboot" \
			|| error "Could not save need to reboot"
	fi
}

init() {
	cleanup
	gen_newversion

	init_vars
	save_vars
}

init
