init() {
	rootdev="$(cat "$SCRIPTSDIR/rootdev")" \
		|| error "Could not read rootdev from prepare step?!"
	partdev="$rootdev"
	[ "${partdev#/dev/mmcblk}" = "$partdev" ] \
		|| partdev="${rootdev}p"

	ab="$(cat "$SCRIPTSDIR/ab")" \
		|| error "Could not read ab from prepare step?!"

	if [ -e "$SCRIPTSDIR/needs_reboot" ]; then
		needs_reboot=1
	fi

	if [ -f "$SCRIPTSDIR/update_rootfs" ]; then
		update_rootfs=$(cat "$SCRIPTSDIR/update_rootfs") \
			|| error "Could not read update_rootfs variable but file existed?!"
	fi
}

init
