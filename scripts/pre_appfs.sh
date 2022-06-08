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
		echo "Could not unmount $dir but we really want the space back: reboot and hope swupdate will run again." >&2
		echo "Note containers will not be able to run after reboot." >&2
		reboot
		# reboot returns immediately but takes time: wait for it.
		sleep infinity
	fi
}

podman_killall() {
	if [ -n "$(podman ps --format '{{.ID}}')" ]; then
		warning "$@"
		podman kill -a
		podman ps --format '{{.ID}}' \
			| timeout 30s xargs -r podman wait
	fi
	podman pod rm -a -f
	podman rm -a -f
}

check_update_disk_encryption() {
	# reencrypt partition if required
	# note we do not reformat as plain if var is not set
	[ -z "$(mkswu_var ENCRYPT_USERFS)" ] && return

	# already encrypted ?
	[ "$(lsblk -n -o type "$dev")" = "crypt" ]  && return

	# if swupdate runs in /var/tmp, we cannot reencrypt it
	[ "${SCRIPTSDIR#/var/tmp}" = "$SCRIPTSDIR" ] \
		|| error "Disk reencryption was requested, but swupdate runs in /var/tmp so we cannot do it" \
			 "Re-run with TMPDIR=/tmp swupdate ... to force installation"

	findmnt -n -o TARGET "$dev" \
		| while read -r mntpoint; do
			# umount if used
			podman_killall "Stopping all containers to dismount fs for disk encryption setup"
			fuser -k "$mntpoint"
			sleep 1
			umount "$mntpoint" \
				|| error "encryption was requested for appfs but could not umount $mntpoint: aborting. Manually dismount it first"
		done \
		|| exit 1

	warning "Reformatting appfs with encryption, current container images and volumes" \
		"Also, in case of update failure or rollback current system will not be able to mount it"

	luks_format "${partdev##*/}5"
	mkfs.btrfs -L app -m DUP -R free-space-tree "$dev" \
		|| error "Could not format btrfs onto $dev after encryption setup"
	mount "$dev" "$basemount" \
		|| error "Could not mount freshly created encrypted appfs"
	btrfs_subvol_create "tmp" || error "Could not create tmp subvol"
	umount "$basemount" \
		|| error "Could not umount appfs"
	mount "$dev" /var/tmp -o "$mountopt=tmp" \
		|| error "Could not remount /var/tmp on host. Further swu install will fail unless manually fixed"

	sed -i -e "s:[^ \t]*p5\t:$dev\t:" /target/etc/fstab \
		|| error "Could not update fstab for encrypted /var/log"
}

prepare_appfs() {
	local dev
	local mountopt="compress=zstd:3,space_cache=v2,subvol"
	local basemount

	basemount=$(mktemp -d -t btrfs-root.XXXXXX) || error "Could not create temp dir"
	mkdir -p /target/var/lib/containers/storage_readonly
	mkdir -p /target/var/lib/containers/storage
	mkdir -p /target/var/app/rollback/volumes
	mkdir -p /target/var/app/volumes /target/var/tmp

	dev=$(findmnt -nv -o SOURCE /var/tmp)
	[ -n "$dev" ] || error "Could not find appfs source device"
	check_update_disk_encryption

	mount "$dev" "$basemount" -o "${mountopt%,subvol}" \
		|| error "Could not mount appfs"

	if grep -q 'graphroot = "/var/lib/containers/storage' /etc/containers/storage.conf 2>/dev/null; then
		podman_killall "Persistent storage is used for podman, stopping all containers before taking snapshot" \
			       "This is only for development, do not use this mode for production!"
	fi

	if [ -n "$(mkswu_var CONTAINER_CLEAR)" ]; then
		podman_killall "CONTAINER_CLEAR requested: stopping and destroying all container data first"
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

	mount -t btrfs -o "$mountopt=boot_${ab}/containers_storage" \
			"$dev" /target/var/lib/containers/storage_readonly \
		|| error "Could not mount containers_storage subvol"
	mount -t btrfs -o "$mountopt=boot_${ab}/volumes" \
			"$dev" /target/var/app/rollback/volumes \
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
	# also, skip on test
	if [ -z "$(mkswu_var SKIP_APP_SUBVOL_SYNC)" ]; then
		stdout_info echo "Waiting for btrfs to flush deleted subvolumes"
		timeout 30m btrfs subvolume sync "$basemount"
	fi
	umount "$basemount"
	rmdir "$basemount"
}

prepare_appfs
