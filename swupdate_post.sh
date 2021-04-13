#!/bin/sh

TMPDIR=${TMPDIR:-/tmp}
mmcblk=
ab=
needs_reboot=
force_reboot=

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
	if [ -e "$TMPDIR/nothing_to_do" ]; then
		rm -f "$TMPDIR/nothing_to_do"
		exit 0
	fi

	mmcblk="$(cat "$TMPDIR/mmcblk")" \
		|| error "Could not read mmcblk from prepare step?!"
	ab="${mmcblk##* }"
	mmcblk="${mmcblk% *}"

	if [ -e "$TMPDIR/needs_reboot" ]; then
		needs_reboot=1
		rm -f "$TMPDIR/needs_reboot"
	fi


	rm -f "$TMPDIR/mmcblk"
}

needs_reboot() {
	[ -n "$needs_reboot" ]
}

umount_if_mountpoint() {
	local dir="$1"
	if ! awk '$5 == "'"$dir"'" { exit 1 }' < /proc/self/mountinfo; then
		umount "$dir" || error "Could not umount $dir"
	fi
}

sideload_containers() {
	local f

	for f in /target/var/tmp/podman_update/container_*.tar; do
		[ -e "$f" ] || continue
		podman_update --storage /target/var/app/storage -l "$f"
	done
	# /mnt files must be signed, while the ones in /target have been
	# verified by swupdate
	for f in /target/var/tmp/podman_update/container_*.usb; do
		[ -e "$f" ] || continue
		f="${f## /}"
		f="/mnt/${f%.usb}.tar"
		[ -e "$f" ] || error "USB container requested but $f not found"
		podman_update --storage /target/var/app/storage \
			--pubkey /etc/swupdate.pem -l "$f"
	done
	for f in /target/var/tmp/podman_update/container_*.pull; do
		[ -e "$f" ] || continue
		podman_update --storage /target/var/app/storage "$(cat "$f")"
	done

	podman_cleanup --storage /target/var/app/storage \
		--confdir /target/etc/atmark/containers

	# sometimes podman mounts this on pull?
	umount_if_mountpoint /target/var/app/storage/overlay

	btrfs property set -ts /target/var/app/storage ro true
}

swap_btrfs_snapshots() {
	# XXX racy/not failure-safe
	# XXX also check return codes, but what if it fails in the middle?...
	# Could make the directory containing storages/volumes_ab a subvolume
	# itself (or just a subdirectory) and swap just that single directory
	# with renameat(.., RENAME_EXCHANGE) -- but no existing program expose
	# this feature.
	rm -rf "$basemount/storage_tmp" "$basemount/volumes_tmp"
	mv "$basemount/storage_0" "$basemount/storage_tmp"
	mv "$basemount/storage_1" "$basemount/storage_0"
	mv "$basemount/storage_tmp" "$basemount/storage_1"
	mv "$basemount/volumes_0" "$basemount/volumes_tmp"
	mv "$basemount/volumes_1" "$basemount/volumes_0"
	mv "$basemount/volumes_tmp" "$basemount/volumes_1"

	# we need to now remount the volumes with the new data,
	# so stop all countainers and restart them
	podman kill -a || return 1
	podman rm -a || return 1
	umount /var/app/storage || return 1
	mount /var/app/storage || return 1
	umount /var/app/volumes || return 1
	mount /var/app/volumes || return 1
	podman_start -a
}

cleanup_appfs() {
	local dev="${mmcblk}p4"
	local basemount

	if ! needs_reboot; then
		basemount=$(mktemp -d -t btrfs-root.XXXXXX)
		mount "$dev" "$basemount" || error "Could not mount app root"

		# We're not rebooting, so we want updated apps to point to
		# current running os and $ab to point to old (current) apps
		# so a fallback gives back what is running right now.
		if ! swap_btrfs_snapshots; then
			umount "$basemount"
			rmdir "$basemount"
			force_reboot=1
			return
		fi
		umount "$basemount"
		rmdir "$basemount"
		podman_start -a
		return
	fi
}

umount_rootfs() {
	umount_if_mountpoint /target/var/app/storage
	umount_if_mountpoint /target/var/app/volumes
	umount_if_mountpoint /target/var/app/volumes_persistent
	umount_if_mountpoint /target/var/tmp
	umount_if_mountpoint /target
}

update_running_versions() {
	# atomic update for running sw versions
	mount --bind / /target || error "Could not bind mount rootfs"
	mount -o remount,rw /target || error "Could not make rootfs rw"
	"$@" < /target/etc/sw-versions > /target/etc/sw-versions.new \
		&& mv /target/etc/sw-versions.new /target/etc/sw-versions
	umount /target || error "Could not umount rootfs rw copy"
}

cleanup_rootfs() {
	# three patterns:
	# - we wrote some data and need rebooting:
	#   * rootfs flag was cleared by pre script if set
	# - we didn't write anything, but don't have other_rootfs_uptodate flag
	#   * set flag in both version files
	# - we didn't write anything and flag is already set
	#   * nothing to do
	if ! needs_reboot; then
		# if we're not rebooting, the other rootfs is now up to date
		grep -q "other_rootfs_uptodate" "/etc/sw-versions" && return
		echo "other_rootfs_uptodate 1" >> /target/etc/sw-versions
		update_running_versions sed -e '$aother_rootfs_uptodate 1'
	fi

	grep -v "other_rootfs_uptodate" "$TMPDIR/sw-versions.merged" > \
		"/target/etc/sw-versions"

	rm -f "$TMPDIR/sw-versions.merged" "$TMPDIR/sw-versions.present"

	if [ "$mmcblk" = "/dev/mmcblk2" ]; then
		cat > /target/etc/fw_env.config <<EOF
${mmcblk}boot${ab} 0x3fe000 0x2000
${mmcblk}boot${ab} 0x3fa000 0x2000
EOF
	fi

	sed -i -e "s/storage_[01]/storage_${ab}/" \
		-e "s/volumes_[01]/volumes_${ab}/" /target/etc/fstab
}

cleanup_uboot() {
	local dev

	if dev=$(readlink -e /dev/swupdate_ubootdev) && [ "${dev#/dev/loop}" != "$dev" ]; then
		losetup -d "$dev" >/dev/null 2>&1
	fi
	rm -f /dev/swupdate_ubootdev

	if ! needs_reboot; then
		return
	fi

	if [ "$mmcblk" = "/dev/mmcblk2" ]; then
		mmc bootpart enable "$((ab+1))" 0 "$mmcblk" \
			|| error "Could not flip mmc boot flag"
		reboot
	fi
}

init
sideload_containers
cleanup_appfs
cleanup_rootfs
umount_rootfs
cleanup_uboot

[ -n "$force_reboot" ] && reboot

# required to have 0 exit code if we don't force reboot
true
