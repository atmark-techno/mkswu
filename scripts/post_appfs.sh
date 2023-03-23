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
		warning "$@"
		podman_info stop -a
		podman ps --format '{{.ID}}' \
			| timeout 20s xargs -r podman_info wait
	fi
	podman_info pod rm -a -f
	podman_info rm -a -f
}

swap_btrfs_snapshots() {
	exchange_btrfs_snapshots || return 1

	# we need to now remount the volumes with the new data,
	# so stop all countainers and restart them
	podman_killall "Stopping containers to swap storage"

	if ! umount -R /var/lib/containers/storage_readonly \
	    || ! mount /var/lib/containers/storage_readonly \
	    || ! umount /var/app/rollback/volumes \
	    || ! mount /var/app/rollback/volumes \
	    || ! podman_start -a; then
		# hope rollback works...
		exchange_btrfs_snapshots
		return 1
	fi
}

check_warn_new_containers_removed() {
	awk '
		NR==FNR {
			x[$1]=1
		}
		NR!=FNR && ! x[$1] {
			print $1;
			x[$1]=1
		}' \
		"$SCRIPTSDIR/podman_images_pre" \
		"$SCRIPTSDIR/podman_images_post" \
		> "$SCRIPTSDIR/podman_images_new" \
		|| error "Could not compare list of podman images?"

	[ -s "$SCRIPTSDIR/podman_images_new" ] || return
	podman_list_images > "$SCRIPTSDIR/podman_images_cleaned"

	while read -r added_image; do
		grep -qw "$added_image" "$SCRIPTSDIR/podman_images_cleaned" \
			&& continue
		image_name=$(awk -v img="$added_image" '
			$1 == img {
				print $2;
				exit
			}' "$SCRIPTSDIR/podman_images_post")
		[ -n "$image_name" ] || image_name="$added_image"
		warning "Container image $image_name was added in swu but immediately removed" \
			"Please use it in /etc/atmark/containers.d if you would like to keep it"
	done < "$SCRIPTSDIR/podman_images_new"
}


cleanup_appfs() {
	local dev basemount
	local cleanup_fail="--fail-missing"

	if grep -q 'graphroot = "/var/lib/containers/storage' /etc/containers/storage.conf 2>/dev/null; then
		# make sure mount point exists in destination image
		mkdir -p /target/var/lib/containers/storage
		# .. and do not complain if an image is not in readonly store
		cleanup_fail=""
	fi

	podman_list_images > "$SCRIPTSDIR/podman_images_post"

	stdout_info echo "Removing unused containers"
	stdout_info "$SCRIPTSDIR/podman_cleanup" --storage /target/var/lib/containers/storage_readonly \
		--confdir /target/etc/atmark/containers $cleanup_fail \
		|| error "cleanup of old images failed: mismatching configuration/container update?"

	# cleanup readonly storage
	[ -z "$(podman ps --root /target/var/lib/containers/storage_readonly -qa)" ] \
		|| error "podman state is not clean"
	rm -f "/target/var/lib/containers/storage_readonly/libpod/bolt_state.db"
	umount_if_mountpoint /target/var/lib/containers/storage_readonly/overlay
	btrfs property set -ts /target/var/lib/containers/storage_readonly ro true

	# if new images were installed, check that we did not remove any of
	# the new images during cleanup.
	if ! cmp -s "$SCRIPTSDIR/podman_images_pre" "$SCRIPTSDIR/podman_images_post"; then
		check_warn_new_containers_removed
		rm -f "$SCRIPTSDIR/podman_images_new" "$SCRIPTSDIR/podman_images_cleaned"
	fi
	rm -f "$SCRIPTSDIR/podman_images_pre" "$SCRIPTSDIR/podman_images_post"


	if ! needs_reboot; then
		dev=$(findmnt -nr --nofsroot -o SOURCE /var/tmp)
		[ -n "$dev" ] || error "Could not find appfs source device"
		basemount=$(mktemp -d -t btrfs-root.XXXXXX) || error "Could not create temp dir"
		mount -t btrfs "$dev" "$basemount" || error "Could not mount app root"

		# We're not rebooting, since we got here there was something
		# to do and want to use updated apps on currenet os (old apps
		# now being backup for fallback)
		if ! swap_btrfs_snapshots; then
			stdout_warn echo "Could not swap btrfs subvolumes, forcing reboot"
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
