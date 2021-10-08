swap_btrfs_snapshots() {
	if command -v renameat2 >/dev/null; then
		renameat2 --exchange "$basemount/boot_0" "$basemount/boot_1"
	else
		# racy implementation, let's hope we don't power down at this point...
		rm -rf "$basemount/boot_tmp"
		if ! mv "$basemount/boot_0" "$basemount/boot_tmp"; then
			return 1
		fi
		if ! mv "$basemount/boot_1" "$basemount/boot_0"; then
			# hope rollback works!!
			mv "$basemount/boot_tmp" "$basemount/boot_0"
			return 1
		fi
		if ! mv "$basemount/boot_tmp" "$basemount/boot_1"; then
			mv "$basemount/boot_0" "$basemount/boot_1"
			mv "$basemount/boot_tmp" "$basemount/boot_0"
			return 1
		fi

	fi

	# we need to now remount the volumes with the new data,
	# so stop all countainers and restart them
	podman kill -a
	podman rm -a
	umount /var/lib/containers/storage_readonly || return 1
	mount /var/lib/containers/storage_readonly || return 1
	umount /var/app/rollback/volumes || return 1
	mount /var/app/rollback/volumes || return 1
	podman_start -a || return 1
}

cleanup_appfs() {
	local dev="${partdev}5"
	local basemount

	"$SCRIPTSDIR/podman_cleanup" --storage /target/var/lib/containers/storage_readonly \
		--confdir /target/etc/atmark/containers

	# sometimes podman mounts this on pull?
	umount_if_mountpoint /target/var/lib/containers/storage_readonly/overlay

	btrfs property set -ts /target/var/lib/containers/storage_readonly ro true

	if grep -q 'graphroot = "/var/lib/containers/storage' /etc/containers/storage.conf 2>/dev/null; then
		# make sure mount point exists in destination image
		mkdir -p /target/var/lib/containers/storage
	fi

	if ! needs_reboot; then
		basemount=$(mktemp -d -t btrfs-root.XXXXXX) || error "Could not create temp dir"
		mount "$dev" "$basemount" || error "Could not mount app root"

		# We're not rebooting, since we got here there was something
		# to do and want to use updated apps on currenet os (old apps
		# now being backup for fallback)
		if ! swap_btrfs_snapshots; then
			echo "Could not swap btrfs subvolumes, forcing reboot"
			umount "$basemount"
			rmdir "$basemount"
			needs_reboot=1
			return
		fi
		umount "$basemount"
		rmdir "$basemount"
		podman_start -a
	fi
}

cleanup_appfs
