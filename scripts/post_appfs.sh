# SPDX-License-Identifier: MIT

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
	touch "$MKSWU_TMP/podman_containers_killed"
	if [ -n "$(podman ps --format '{{.ID}}')" ]; then
		warning "$@"
		podman_info kill -a -s SIGTERM
		if ! podman ps --format '{{.ID}}' | timeout 10s xargs -r podman wait; then
			podman_info kill -a -s SIGKILL
			podman ps --format '{{.ID}}' | timeout 20s xargs -r podman wait
		fi
	fi
	podman_info pod rm -a -f
	podman_info rm -a -f
}

swap_btrfs_snapshots() {
	exchange_btrfs_snapshots || return 1

	# we need to now remount the volumes with the new data,
	# so stop all containers and restart them
	podman_killall "Stopping containers to swap storage"

	# if not running from init namespace we need to remound there, as that is
	# what will be left after update.
	# We do not need to do it in current namespace as nothing else will use
	# podman after this.
	local nsenter=""
	[ "$(readlink /proc/1/ns/mnt)" = "$(readlink /proc/self/ns/mnt)" ] || nsenter=1

	# (cannot use internal functions, same as in pre_appfs, for recursive umount)
	if umount --version 2>/dev/null | grep -q util-linux; then
                set -- umount -R
        else
                set -- abos-ctrl umount
        fi

	if ! ${nsenter:+nsenter -t 1 -m} "$@" /var/lib/containers/storage_readonly \
	    || ! ${nsenter:+nsenter -t 1 -m} mount /var/lib/containers/storage_readonly \
	    || ! ${nsenter:+nsenter -t 1 -m} "$@" /var/app/rollback/volumes \
	    || ! ${nsenter:+nsenter -t 1 -m} mount /var/app/rollback/volumes; then
		# hope rollback works... will reboot at end of update
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
		"$MKSWU_TMP/podman_images_pre" \
		"$MKSWU_TMP/podman_images_post" \
		> "$MKSWU_TMP/podman_images_new" \
		|| error "Could not compare list of podman images?"

	[ -s "$MKSWU_TMP/podman_images_new" ] || return
	podman_list_images > "$MKSWU_TMP/podman_images_cleaned"

	while read -r added_image; do
		grep -qw "$added_image" "$MKSWU_TMP/podman_images_cleaned" \
			&& continue
		image_name=$(awk -v img="$added_image" '
			$1 == img {
				print $2;
				exit
			}' "$MKSWU_TMP/podman_images_post")
		[ -n "$image_name" ] || image_name="$added_image"
		warning "Container image $image_name was added in swu but immediately removed" \
			"Please use it in /etc/atmark/containers if you would like to keep it"
	done < "$MKSWU_TMP/podman_images_new"
}

remove_unused_containers() {
	info "Removing unused containers"
	stdout_info "$SCRIPTSDIR/podman_cleanup" \
			--confdir /target/etc/atmark/containers --ab "$ab" \
			"$@" \
		|| error "cleanup of old images failed: mismatching configuration/container update?"
}

cleanup_appfs() {
	local dev basemount

	podman_list_images > "$MKSWU_TMP/podman_images_post"

	if grep -q 'graphroot = "/var/lib/containers/storage' /etc/containers/storage.conf 2>/dev/null; then
		# make sure mount point exists in destination image
		mkdir -p /target/var/lib/containers/storage
		# ... and nag user
		warning "containers running on development storage, image removal only removes untagged images"
		# only purge images without tags
		remove_unused_containers --storage /var/lib/containers/storage
	else
		remove_unused_containers --storage /target/var/lib/containers/storage_readonly \
			--trim-tags --fail-missing
	fi

	# cleanup readonly storage
	[ -z "$(podman ps --root /target/var/lib/containers/storage_readonly -qa)" ] \
		|| error "podman state is not clean"
	rm -f "/target/var/lib/containers/storage_readonly/libpod/bolt_state.db" \
		"/target/var/lib/containers/storage_readonly/db.sql"
	umount_if_mountpoint /target/var/lib/containers/storage_readonly/overlay \
		|| error "could not umount /target/var/lib/containers/storage_readonly/overlay"
	btrfs property set -ts /target/var/lib/containers/storage_readonly ro true

	# if new images were installed, check that we did not remove any of
	# the new images during cleanup.
	if ! cmp -s "$MKSWU_TMP/podman_images_pre" "$MKSWU_TMP/podman_images_post"; then
		check_warn_new_containers_removed
		rm -f "$MKSWU_TMP/podman_images_new" "$MKSWU_TMP/podman_images_cleaned"
	fi
	rm -f "$MKSWU_TMP/podman_images_pre" "$MKSWU_TMP/podman_images_post"


	if ! needs_reboot; then
		dev=$(findmnt -nr --nofsroot -o SOURCE /var/tmp)
		[ -n "$dev" ] || error "Could not find appfs source device"
		basemount=/target/mnt
		mount -t btrfs "$dev" "$basemount" || error "Could not mount app root"

		# We're not rebooting, since we got here there was something
		# to do and want to use updated apps on current os (old apps
		# now being backup for fallback)
		if ! swap_btrfs_snapshots; then
			stdout_warn echo "Could not swap btrfs subvolumes, forcing reboot"
			umount "$basemount"
			needs_reboot=1
			return
		fi
		umount "$basemount"
		# note failure after this will be in bad installed state but sw-versions
		# is not correct... Hopefully should not happen, and it's better than
		# updating sw-versions first (and miss an update)
	fi
}

cleanup_appfs
