#!/bin/sh

update_id=
mmcblk=
ab=

error() {
	echo "$@" >&2
	exit 1
}

get_vers() {
	local component="$1"
	local source="${2:-$TMPDIR/sw-versions.present}"

	awk '$1 == "'"$component"'" { print $2 }' < "$source"
}

need_update() {
	local component="$1"
	local newvers oldvers

	newvers=$(get_vers "$component")
	[ -n "$newvers" ] || return 1

	oldvers=$(get_vers "$component" /etc/sw-versions)
	[ "$newvers" != "$oldvers" ]
}

init() {
	mmcblk="$(cat "$TMPDIR/mmcblk")" \
		|| error "Could not read mmcblk from prepare step?!"
	ab="${mmcblk##* }"
	mmcblk="${mmcblk# *}"

	update_id=$(cat "$TMPDIR/update_id") \
		|| error "Could not read update_id from prepare step?!"


	rm -f "$TMPDIR/mmcblk"
	rm -f "$TMPDIR/update_id"
}

needs_reboot() {
	# XXX do in pre and read var?
	:
}


cleanup_appfs() {
	# XXX update links for storage/volume
	# XXX fix fstab to use update_id
	# XXX remove old snapshots
	# XXX remove images linked to containers that no longer exist

	if !needs_reboot; then
		# XXX restart containers that need them
	fi
}

cleanup_rootfs() {
	cp "$TMPDIR/sw-versions.merged" "/target/etc/sw-versions"
	if [ "$mmcblk" = "/dev/mmcblk2" ]; then
		cat > /target/etc/fw_env.config <<EOF
${mmcblk}boot${ab} 0x3fe000 0x2000
${mmcblk}boot${ab} 0x3fa000 0x2000
EOF
	fi
}

cleanup_uboot() {
	local dev

	if dev=$(readlink -e /dev/swupdate_ubootdev) && [ "${dev#/dev/loop}" != "$dev" ]; then
		losetup -d "$dev" >/dev/null 2>&1
	fi
	rm -f /dev/swupdate_ubootdev

	if ! needsreboot; then
		return
	fi

	if [ "$mmcblk" = "/dev/mmcblk2" ]; then
		mmc bootpart enable "$((ab+1))" 0 "$mmcblk" \
			|| error "Could not flip mmc boot flag"
		# XXX test
		#reboot
	fi
}

init
cleanup_appfs
cleanup_rootfs
cleanup_uboot
