exchange_btrfs_snapshots() {
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
}

podman_killall() {
	if [ -n "$(podman ps --format '{{.ID}}')" ]; then
		printf "WARNING: %s\n" "$@" >&2
		podman kill -a
		podman ps --format '{{.ID}}' \
			| timeout 30s xargs podman wait
	fi
	podman pod rm -a -f
	podman rm -a -f
}

swap_btrfs_snapshots() {
	exchange_btrfs_snapshots || return 1

	# we need to now remount the volumes with the new data,
	# so stop all countainers and restart them
	podman_killall "Stopping containers to swap storage"

	if ! umount /var/lib/containers/storage_readonly \
	    || ! mount /var/lib/containers/storage_readonly \
	    || ! umount /var/app/rollback/volumes \
	    || ! mount /var/app/rollback/volumes \
	    || ! podman_start -a; then
		# hope rollback works...
		exchange_btrfs_snapshots
		return 1
	fi
}

cleanup_appfs() {
	local dev="${partdev}5"
	local basemount
	local cleanup_fail="--fail-missing"

	if grep -q 'graphroot = "/var/lib/containers/storage' /etc/containers/storage.conf 2>/dev/null; then
		# make sure mount point exists in destination image
		mkdir -p /target/var/lib/containers/storage
		# .. and do not complain if an image is not in readonly store
		cleanup_fail=""
	fi

	"$SCRIPTSDIR/podman_cleanup" --storage /target/var/lib/containers/storage_readonly \
		--confdir /target/etc/atmark/containers $cleanup_fail \
		|| error "cleanup of old images failed: mismatching configuration/container update?"

	# sometimes podman mounts this on pull?
	umount_if_mountpoint /target/var/lib/containers/storage_readonly/overlay

	btrfs property set -ts /target/var/lib/containers/storage_readonly ro true

	if ! needs_reboot; then
		basemount=$(mktemp -d -t btrfs-root.XXXXXX) || error "Could not create temp dir"
		mount "$dev" "$basemount" || error "Could not mount app root"

		# We're not rebooting, since we got here there was something
		# to do and want to use updated apps on currenet os (old apps
		# now being backup for fallback)
		if ! swap_btrfs_snapshots; then
			echo "Could not swap btrfs subvolumes, forcing reboot" >&2
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
