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

btrfs_subvol_recursive_recreate() {
	local vol="$1" mntpoint="$2"
	[ -e "$basemount/$vol" ] || return 1
	# delete subvolumes by id to avoid dealing with paths.
	# subvol list -o prints something like "ID 123 gen..." for child subvolumes.
	btrfs subvol list -o "$basemount/$vol" \
		| while read -r _ id _; do
			btrfs subvol delete -i "$id" "$basemount"
		done
	btrfs_subvol_recreate "$vol" "$mntpoint"
}

btrfs_subvol_recreate() {
	local vol="$1" mntpoint="$2"

	[ -e "$basemount/$vol" ] || return 1

	btrfs subvolume delete "$basemount/$vol" \
		|| error "Could not remove $vol"

	# Recreate subvol immediately so things work after reboot
	btrfs subvol create "$basemount/$vol" \
		|| error "Could not re-create $vol"

	# ... and also try to remount it now if mounted:
	# - umount so `btrfs subvol sync` does not hang
	# - remount so podman commands work as expected
	# (in particular 'containers_storage' is required swupdate itself
	# if in disk mode)
	remount_or_reboot "$mntpoint"
}

remount_failed() {
	echo "Could not unmount/mount $dir but we really want the space back: reboot and hope swupdate will run again." >&2
	echo "Note containers will not be able to run after reboot." >&2
	reboot
	# reboot returns immediately but takes time: wait for it.
	sleep infinity
}

remount_pid1_ns() {
	local dir="$1"

	# if we're in the same namespace as pid 1 just skip this,
	# normal processing is enough
	[ "$(readlink /proc/1/ns/mnt)" = "$(readlink /proc/self/ns/mnt)" ] && return

	# check dir is mounted in init namespace
	is_mountpoint "$dir" 1

	# we cannot use internal functions in nsenter, fall back to either
	# `umount -R` (util-linux) or `abos-ctrl umount` depending on version...
	if umount --version 2>dev/null | grep -q util-linux; then
		set -- umount -R
	else
		set -- abos-ctrl umount
	fi

	if ! nsenter -t 1 -m "$@" "$dir" \
	    || ! nsenter -t 1 -m mount "$dir"; then
		remount_failed
	fi
}

remount_or_reboot() {
	local dir="$1"

	remount_pid1_ns "$dir"

	is_mountpoint "$dir" || return

	if ! umount_if_mountpoint "$dir" || ! mount "$dir"; then
		remount_failed
	fi
}

podman_killall() {
	if [ -n "$(podman ps --format '{{.ID}}')" ]; then
		warning "$@"
		podman_info stop -a
		podman ps --format '{{.ID}}' \
			| timeout 20s xargs -r podman_info wait
		touch "$MKSWU_TMP/podman_containers_killed"
	fi
	podman_info pod rm -a -f
	podman_info rm -a -f
}

check_update_disk_encryption() {
	# reencrypt partition if required
	# note we do not reformat as plain if var is not set
	[ -z "$(mkswu_var ENCRYPT_USERFS)" ] && return

	# already encrypted ?
	[ "$(lsblk -n -o type "$dev")" = "crypt" ]  && return

	# if swupdate runs in /var/tmp, we cannot reencrypt it
	[ "${MKSWU_TMP#/var/tmp}" = "$MKSWU_TMP" ] \
		|| error "Disk reencryption was requested, but swupdate runs in /var/tmp so we cannot do it" \
			 "Re-run with TMPDIR=/tmp swupdate ... to force installation"

	findmnt -nr -o TARGET "$dev" \
		| while read -r mntpoint; do
			# umount if used
			podman_killall "Stopping all containers to dismount fs for disk encryption setup"
			fuser -k "$mntpoint"
			sleep 1
			umount "$mntpoint" \
				|| error "encryption was requested for appfs but could not umount $mntpoint: aborting. Manually dismount it first"
		done \
		|| exit 1

	warning "Reformatting appfs with encryption, current container images and" \
		"volumes will be lost."

	luks_format "${partdev##*/}5"
	mkfs.btrfs -L app -m DUP -R free-space-tree "$dev" \
		|| error "Could not format btrfs onto $dev after encryption setup"
	mount -t btrfs "$dev" "$basemount" \
		|| error "Could not mount freshly created encrypted appfs"
	btrfs_subvol_create "tmp" || error "Could not create tmp subvol"
	# this is only for rollback - don't fail on error
	mkdir "$basemount/boot_$((!ab))"
	btrfs_subvol_create "boot_$((!ab))/containers_storage"
	btrfs_subvol_create "boot_$((!ab))/volumes"
	umount "$basemount" \
		|| error "Could not umount appfs"
	mount -t btrfs "$dev" /var/tmp -o "$mountopt=tmp" \
		|| error "Could not remount /var/tmp on host. Further swu install will fail unless manually fixed"

	if ! sed -i -e "s:[^ \t]*p5\t:$dev\t:" /etc/fstab \
	    || ! persist_file /etc/fstab; then
		warning "Could not update the current rootfs fstab for encrypted appfs," \
			"will not be able to mount /var/log in case of rollback"
	fi
	sed -i -e "s:[^ \t]*p5\t:$dev\t:" /target/etc/fstab \
		|| error "Could not update fstab for encrypted appfs"
}

prepare_appfs() {
	local dev basemount
	local mountopt="compress=zstd:3,subvol"

	mkdir -p /target/var/lib/containers/storage_readonly
	mkdir -p /target/var/lib/containers/storage
	mkdir -p /target/var/app/rollback/volumes
	mkdir -p /target/var/app/volumes /target/var/tmp
	basemount=/target/mnt

	dev=$(findmnt -nr --nofsroot -o SOURCE /var/tmp)
	[ -n "$dev" ] || error "Could not find appfs source device"
	check_update_disk_encryption

	mount -t btrfs "$dev" "$basemount" -o "${mountopt%,subvol}" \
		|| error "Could not mount appfs"

	if grep -q 'graphroot = "/var/lib/containers/storage' /etc/containers/storage.conf 2>/dev/null; then
		podman_killall "Persistent storage is used for podman, stopping all containers before updating"
	fi

	[ -d "$basemount/boot_0" ] || mkdir "$basemount/boot_0"
	[ -d "$basemount/boot_1" ] || mkdir "$basemount/boot_1"
	if [ -n "$(mkswu_var CONTAINER_CLEAR)" ]; then
		podman_killall "CONTAINER_CLEAR requested: stopping all containers first"
		info "Destroying all container data (CONTAINER_CLEAR)"

		btrfs_subvol_recreate "boot_$((!ab))/containers_storage" \
			"/var/lib/containers/storage_readonly"
		btrfs_subvol_recreate "boot_$((!ab))/volumes" \
			"/var/app/rollback/volumes"
		# A6E uses subvolumes for device-local data
		btrfs_subvol_recursive_recreate "volumes" \
			"/var/app/volumes"
		btrfs_subvol_recreate "containers_storage" \
			"/var/lib/containers/storage"
	fi

	btrfs_snapshot_or_create "boot_$((!ab))/containers_storage" "boot_${ab}/containers_storage" \
		|| error "Could not create containers_storage subvol"
	btrfs_snapshot_or_create "boot_$((!ab))/volumes" "boot_${ab}/volumes" \
		|| error "Could not create rollback/volumes subvol"
	btrfs_subvol_create "volumes" \
		|| error "Could not create volumes subvol"

	if mountpoint -q /var/lib/containers/storage; then
		mount --bind /var/lib/containers/storage \
				/target/var/lib/containers/storage \
			|| error "Could not bind mount persistent storage"
	fi
	mount -t btrfs -o "$mountopt=boot_${ab}/containers_storage" \
			"$dev" /target/var/lib/containers/storage_readonly \
		|| error "Could not mount containers_storage subvol"
	mount -t btrfs -o "$mountopt=boot_${ab}/volumes" \
			"$dev" /target/var/app/rollback/volumes \
		|| error "Could not mount rollback/volume subvol"
	# ignore swdesc_exec "chroot" lines...
	if sed -e 's@-v /target/var/app/volumes:/var/app/volumes@@g' "$SWDESC" 2>/dev/null \
			| grep -qF "/var/app/volumes"; then
		warning "Mounting /var/app/volumes for target" \
			"This partition is not safe to modify from update while in use," \
			"consider using /var/app/rollback/volumes for updates instead."
		mount -t btrfs -o "$mountopt=volumes" "$dev" /target/var/app/volumes \
			|| error "Could not mount volume subvol"
	else
		echo "Skipping /var/app/volumes mount"
		# mount an empty tmpfs instead so any write there will fail
		# tmpfs size cannot be 0: set 1 (one page in practice) and make ro
		mount -t tmpfs -o size=1,ro=1 tmpfs /target/var/app/volumes \
			|| error "Could not mount tmpfs on /var/app/volumes"
	fi
	mount -t btrfs -o "$mountopt=tmp" "$dev" /target/var/tmp \
		|| error "Could not mount tmp subvol"

	podman_list_images > "$MKSWU_TMP/podman_images_pre"

	# wait for subvolume deletion to complete to make sure we can use
	# any reclaimed space
	# In some rare case this can get stuck (files open or subvolume
	# explicitely mounted by name, which can happen if fstab got setup
	# incorrectly somehow).
	# add an unreasonably long timeout just in case.
	# also, skip on test
	if [ -z "$(mkswu_var SKIP_APP_SUBVOL_SYNC)" ]; then
		info "Waiting for btrfs to flush deleted subvolumes"
		if ! timeout 30m btrfs subvolume sync "$basemount"; then
			warning "Could not wait for btrfs subvolumes to be deleted." \
				"There might be a problem with current mount points, but update can continue."
			info "Listing current mount points for reporting:"
			# get mount points for all mount namespaces
			# stat output and awk variables (we double-check $4 is pure digit):
			# '/proc/10/ns/mnt' -> 'mnt:[4026531840]'
			# 123    4  5  6   7    8                9
			stat -c %N /proc/[0-9]*/ns/mnt \
				| awk -F"['/]" '!seen[$8] && $4 ~ /^[0-9]+$/ {
						seen[$8]=1; print $4;
					}' \
				| while read -r pid; do
					# shellcheck disable=SC2016 ## don't expand $1 here..
					ps x | stdout_info awk -v "pid=$pid" '$1 == pid'
					stdout_info findmnt -N "$pid" -t btrfs,ext4
				done
		fi
	fi
	umount "$basemount"
}

prepare_appfs
