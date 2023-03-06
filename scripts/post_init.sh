# Do minimal work if called from installer
post_installer() {
	# for update_shadow compat, always mounted in installer
	local fsroot=/live/rootfs

	# update_shadow checks user password has been set unless made optional
	update_shadow
	# update swupdate certificate and versions
	update_swupdate_certificate
	cp "$SCRIPTSDIR/sw-versions.merged" "/target/etc/sw-versions" \
		|| error "Could not set sw-versions"
}

init() {
	if [ -n "$SWUPDATE_FROM_INSTALLER" ]; then
		post_installer
		exit 0
	fi

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
