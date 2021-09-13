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

	if grep -q 'graphroot = "/var/lib/containers/storage' /target/etc/containers/storage.conf 2>/dev/null; then
		echo "Persistent storage is used for podman, stopping all containers before taking snapshot" >&2
		echo "This is only for development, do not use this mode for production!" >&2
		podman kill -a
		podman rm -a
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

	rm -rf "/target/var/tmp/podman_update"
	mkdir "/target/var/tmp/podman_update" \
		|| error "Could not create /target/var/tmp/podman_update"

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
