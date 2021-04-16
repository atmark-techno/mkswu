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

sideload_containers
cleanup_appfs
