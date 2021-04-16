swap_btrfs_snapshots() {
	# XXX racy/not failure-safe
	# XXX also check return codes, but what if it fails in the middle?...
	# Could make the directory containing storages/volumes_ab a subvolume
	# itself (or just a subdirectory) and swap just that single directory
	# with renameat(.., RENAME_EXCHANGE) -- but no existing program expose
	# this feature.
	rm -rf "$basemount/storage_tmp" "$basemount/volumes_tmp"
	mv "$basemount/storage_0" "$basemount/storage_tmp" \
		&& mv "$basemount/storage_1" "$basemount/storage_0" \
		&& mv "$basemount/storage_tmp" "$basemount/storage_1" \
		&& mv "$basemount/volumes_0" "$basemount/volumes_tmp" \
		&& mv "$basemount/volumes_1" "$basemount/volumes_0" \
		&& mv "$basemount/volumes_tmp" "$basemount/volumes_1" \
		|| error "Could not swap podman storage/volumes subvolumes"

	# we need to now remount the volumes with the new data,
	# so stop all countainers and restart them
	podman kill -a
	podman rm -a
	umount /var/app/storage || return 1
	mount /var/app/storage || return 1
	umount /var/app/volumes || return 1
	mount /var/app/volumes || return 1
	podman_start -a || return 1
}

cleanup_appfs() {
	local dev="${mmcblk}p4"
	local basemount

	"$SCRIPTSDIR/podman_cleanup" --storage /target/var/app/storage \
		--confdir /target/etc/atmark/containers

	# sometimes podman mounts this on pull?
	umount_if_mountpoint /target/var/app/storage/overlay
	btrfs property set -ts /target/var/app/storage ro true

	if ! needs_reboot; then
		basemount=$(mktemp -d -t btrfs-root.XXXXXX)
		mount "$dev" "$basemount" || error "Could not mount app root"

		# We're not rebooting, since we got here there was something
	        # to do and want to use updated apps on currenet os (old apps
		# now being backup for fallback)
		if ! swap_btrfs_snapshots; then
			echo "Could not swap btrfs subvolumes, forcing reboot"
			umount "$basemount"
			rmdir "$basemount"
			force_reboot=1
			return
		fi
		umount "$basemount"
		rmdir "$basemount"
		podman_start -a
	fi
}

cleanup_appfs
