copy_to_target() {
	local file
	local dir

	for file; do
		[ -e "$file" ] || continue

		dir=$(dirname "$file")
		[ -d "/target/$dir" ] || mkdir -p "/target/$dir"
		cp -a "$file" "/target/$file"
	done
}

prepare_rootfs() {
	local dev="${mmcblk}p$((ab+1))"
	local uptodate
	local basemount
	local tmp fail

	# We need /target to exist for update, try hard to create it
	# Note:
	# - we need a known path because that path is used in sw-description
	#   for archives as well as post scripts
	# - we want a path regular users can't hijack e.g. not /tmp or similar
	# - it should almost always already exist, as created for next update
	if ! [ -d /target ]; then
		[ -e /target ] && error "/target exists but is not a directory, update failing"
		if ! mkdir /target 2>/dev/null; then
			# read-only filesystem, remount somewhere else as rw
			# to not impact current fs
			tmp=$(mktemp -d) \
			    && mount --bind / "$tmp" \
			    && mount -o remount,rw "$tmp" \
			    && mkdir "$tmp/target" \
			    || fail=1

			if [ -n "$tmp" ]; then
				umount "$tmp"
				rmdir "$tmp"
			fi
			[ -n "$fail" ] && error "Could not create /target for upgrade, aborting"
		fi
	fi

	# Check if the current copy is up to date.
	# If there is no need to reboot, we can use it -- otherwise we need
	# to clear the flag.
	if grep -q other_rootfs_uptodate /etc/sw-versions 2>/dev/null; then
		if ! needs_reboot; then
			echo "Other fs up to date, reformat"
			mount "$dev" "/target" -o ro || error "Could not mount $dev"
			return
		fi
		echo "Clearing other fs up to date flag"
		grep -v 'other_rootfs_uptodate' /etc/sw-versions \
			> "$TMPDIR/sw-versions.nouptodate"
		update_running_versions "$TMPDIR/sw-versions.nouptodate"
	fi

	# check if partitions exist and create them if not:
	# - XXX boot partitions (always exist?)
	# - XXX gpp partitions
	# sgdisk  --zap-all --new 1:20480:+400M --new 2:0:+400M --new 3:0:+50M --new 4:0:0 /dev/mmcblk2

	# note mkfs.ext4 fails even with -F if the filesystem is mounted
	# somewhere, so this doubles as failguard
	mkfs.ext4 -F "$dev" || error "Could not reformat $dev"
	mount "$dev" "/target" || error "Could not mount $dev"

	mkdir -p /target/boot /target/mnt /target/target

	if needs_update "base_os"; then
		if get_version "kernel" && ! needs_update "kernel"; then
			cp -ax /boot/. /target/boot
		fi

		# copy some files regardless - this echoes the fixups in post_rootfs,
		# but these files can be overriden by update
		copy_to_target /etc/hostname /etc/atmark /etc/motd
		copy_to_target /etc/hwrevision /etc/fstab

		copy_to_target /etc/swupdate.cfg
		copy_to_target /etc/swupdate.pem /etc/swupdate.aes-key

		# sshd
		copy_to_target /etc/runlevels/default/sshd
		copy_to_target /etc/ssh /root/.ssh /home/atmark/.ssh

		# network conf
		copy_to_target /etc/network /etc/resolv.conf
		return
	fi

	# if no update is required copy current fs over
	echo "No base os update: copying current os over"

	basemount=$(mktemp -d -t root-mount.XXXXXX) || error "Could not create temp dir"
	mount --bind / "$basemount" || error "Could not bind mount /"
	cp -ax "$basemount"/. /target/ || error "Could not copy existing fs over"
	umount "$basemount"
	rmdir "$basemount"
}

prepare_rootfs
