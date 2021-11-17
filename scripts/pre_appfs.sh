btrfs_snapshot_or_create() {
	local source="$1"
	local new="$2"

	if [ -e "$basemount/$new" ]; then
		btrfs subvolume delete "$basemount/$new"
	fi
	if [ -e "$basemount/$source" ]; then
		btrfs subvolume snapshot \
			"$basemount/$source" "$basemount/$new"
	else
		btrfs subvolume create "$basemount/$new"
	fi
}

btrfs_subvol_create() {
	local new="$1"

	[ -e "$basemount/$new" ] && return
	btrfs subvolume create "$basemount/$new"
}

btrfs_subvol_delete() {
	local vol="$1"

	[ -e "$basemount/$vol" ] || return 1
	btrfs subvolume delete "$basemount/$vol"
}

umount_or_reboot() {
	local dir="$1"

	is_mountpoint "$dir" || return

	if ! umount "$dir"; then
		echo "Could not unmount $dir but we really want the space back: reboot and hope swupdate will run again. Note containers will not be able to run after reboot." >&2
		reboot
		# reboot returns immediately but takes time: wait for it.
		sleep infinity
	fi
}

prepare_appfs() {
	local dev="${partdev}5"
	local mountopt="compress=zstd:3,space_cache=v2,subvol"
	local basemount

	basemount=$(mktemp -d -t btrfs-root.XXXXXX) || error "Could not create temp dir"
	mkdir -p /target/var/lib/containers/storage_readonly
	mkdir -p /target/var/lib/containers/storage
	mkdir -p /target/var/app/rollback/volumes
	mkdir -p /target/var/app/volumes /target/var/tmp

	if ! mount "$dev" "$basemount" >/dev/null 2>&1; then
		echo "Reformating $dev (app)"
		mkfs.btrfs "$dev" || error "$dev already contains another filesystem (or other mkfs error)"
		mount "$dev" "$basemount" || error "Could not mount $dev"
	fi

	if grep -q 'graphroot = "/var/lib/containers/storage' /etc/containers/storage.conf 2>/dev/null; then
		echo "Persistent storage is used for podman, stopping all containers before taking snapshot" >&2
		echo "This is only for development, do not use this mode for production!" >&2
		podman kill -a
		podman rm -a
	fi

	if grep -q "CONTAINER_CLEAR" "$SWDESC"; then
		echo "CONTAINER_CLEAR requested: stopping and destroying all container data first" >&2
		podman kill -a
		podman rm -a
		btrfs_subvol_delete "boot_0/containers_storage"
		btrfs_subvol_delete "boot_0/volumes"
		btrfs_subvol_delete "boot_1/containers_storage"
		btrfs_subvol_delete "boot_1/volumes"
		btrfs_subvol_delete "volumes"
		if btrfs_subvol_delete "containers_storage"; then
			btrfs_subvol_create "containers_storage"
		fi
		# we need to unmount volumes or btrfs subvolume sync below will hang
		# (and not be able to free space)
		umount_or_reboot /var/lib/containers/storage_readonly/overlay
		umount_or_reboot /var/lib/containers/storage_readonly
		umount_or_reboot /var/lib/containers/storage/overlay
		umount_or_reboot /var/lib/containers/storage
		umount_or_reboot /var/app/rollback/volumes
		umount_or_reboot /var/app/volumes
	fi

	[ -d "$basemount/boot_0" ] || mkdir "$basemount/boot_0"
	[ -d "$basemount/boot_1" ] || mkdir "$basemount/boot_1"
	btrfs_snapshot_or_create "boot_$((!ab))/containers_storage" "boot_${ab}/containers_storage" \
		|| error "Could not create containers_storage subvol"
	btrfs_snapshot_or_create "boot_$((!ab))/volumes" "boot_${ab}/volumes" \
		|| error "Could not create rollback/volumes subvol"
	btrfs_subvol_create "volumes" \
		|| error "Could not create volumes subvol"
	btrfs_subvol_create "tmp" || error "Could not create tmp subvol"

	mount -t btrfs -o "$mountopt=boot_${ab}/containers_storage" "$dev" /target/var/lib/containers/storage_readonly \
		|| error "Could not mount containers_storage subvol"
	mount -t btrfs -o "$mountopt=boot_${ab}/volumes" "$dev" /target/var/app/rollback/volumes \
		|| error "Could not mount rollback/volume subvol"
	mount -t btrfs -o "$mountopt=volumes" "$dev" /target/var/app/volumes \
		|| error "Could not mount volume subvol"
	mount -t btrfs -o "$mountopt=tmp" "$dev" /target/var/tmp \
		|| error "Could not mount tmp subvol"

	# wait for subvolume deletion to complete to make sure we can use
	# any reclaimed space
	# In some rare case this can get stuck (files open or subvolume
	# explicitely mounted by name, which can happen if fstab got setup
	# incorrectly somehow).
	# add an unreasonably long timeout just in case.
	timeout 30m btrfs subvolume sync "$basemount"
	umount "$basemount"
	rmdir "$basemount"
}

prepare_appfs
