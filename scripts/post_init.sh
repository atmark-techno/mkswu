# SPDX-License-Identifier: MIT

# Do minimal work if skipping cleanup (installer or chained updates)
post_minimal() {
	info "$1"

	# check passwords have been set if required
	check_shadow_empty_password
	# update swupdate certificate and versions
	update_swupdate_certificate
	cp "$MKSWU_TMP/sw-versions.merged" "/target/etc/sw-versions" \
		|| error "Could not set sw-versions"

	log_status "SUCCESS"
}

init() {
	if [ -n "$SWUPDATE_FROM_INSTALLER" ]; then
		post_minimal "SWU post install in installer"
		exit 0
	fi
	if [ "$SWUPDATE_CHAIN_IDX" != "$SWUPDATE_CHAIN_COUNT" ]; then
		post_minimal "Skipping post ($SWUPDATE_CHAIN_IDX / $SWUPDATE_CHAIN_COUNT)"
		exit 0
	fi

	rootdev="$(cat "$MKSWU_TMP/rootdev")" \
		|| error "Could not read rootdev from prepare step?!"
	partdev="$rootdev"
	[ "${partdev#/dev/mmcblk}" = "$partdev" ] \
		|| partdev="${rootdev}p"

	ab="$(cat "$MKSWU_TMP/ab")" \
		|| error "Could not read ab from prepare step?!"

	if [ -e "$MKSWU_TMP/needs_reboot" ]; then
		needs_reboot=1
	fi

	if [ -f "$MKSWU_TMP/update_rootfs" ]; then
		update_rootfs=$(cat "$MKSWU_TMP/update_rootfs") \
			|| error "Could not read update_rootfs variable but file existed?!"
	fi
}

init
