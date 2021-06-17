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

	# set storage ro unless main storage
	if [ "$(readlink /etc/containers/storage.conf)" != "storage.conf-persistent" ] &&
	   ! grep -q 'graphroot = "/var/app/storage' /target/etc/atmark/containers-storage.conf 2>/dev/null; then
		btrfs property set -ts /target/var/app/storage ro true
	fi

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
