#!/bin/sh

TMPDIR=/tmp

mmcblk=/dev/mmcblk2
ab=0
needs_reboot=

error() {
	echo "$@" >&2
	exit 1
}

get_version() {
	local component="$1"
	local source="${2:-$TMPDIR/sw-versions.present}"

	awk '$1 == "'"$component"'" { print $2 }' < "$source"
}

# strict greater than
version_higher() {
	local oldvers="$1"
	local newvers="$2"

	! echo -e "$2\n$1" | sort -VC
}

version_update() {
	local component="$1"
	local oldvers="$2"
	local newvers="$3"

	[ -n "$newvers" ] || return 1

	case "$component" in
	uboot|kernel) [ "$newvers" != "$oldvers" ];;
	*) version_higher "$oldvers" "$newvers";;
	esac
}

needs_update() {
	local component="$1"
	local newvers oldvers

	newvers=$(get_version "$component")
	[ -n "$newvers" ] || return 1

	oldvers=$(get_version "$component" /etc/sw-versions)
	version_update "$component" "$oldvers" "$newvers"
}

gen_newversion() {
	local component oldvers newvers

	# extract all present component versions then keep whatever is biggest
	awk -F'[" ]+' '$2 == "name" {component=$4}
		component && $2 == "version" { print component, $4 }
		/,/ { component="" }' < "$TMPDIR/sw-description" |
		sort -Vr | sort -u -k 1,1 > "$TMPDIR/sw-versions.present"
	
	# Merge files, keeping order of original sw-versions,
	# then appending other lines from new one in order as well.
	# Could probably do better but it works and files are small..
	while read -r component oldvers; do
		newvers=$(get_version "$component")
		version_update "$component" "$oldvers" "$newvers" || newvers="$oldvers"
		echo "$component $newvers"
	done < /etc/sw-versions > "$TMPDIR/sw-versions.merged"
	while read -r component newvers; do
		oldvers=$(get_version "$component" /etc/sw-versions)
		[ -z "$oldvers" ] && echo "$component $newvers"
	done < "$TMPDIR/sw-versions.present" >> "$TMPDIR/sw-versions.merged"
}

umount_if_mountpoint() {
	local dir="$1"
	if mountpoint -q "$dir"; then
		umount "$dir" || error "Could not umount $dir"
	fi
}

cleanup_previous_upgrade() {
        umount_if_mountpoint /target/var/app/storage
        umount_if_mountpoint /target/var/app/volumes
        umount_if_mountpoint /target/var/app/volumes_persistent
        umount_if_mountpoint /target/var/app/volumes_tmp
        umount_if_mountpoint /target
	rm -f "$TMPDIR/needs_reboot"
}


init_rootfs() {
	local rootdev

	rootdev=$(sed -ne 's/.*root=\([^ ]*\).*/\1/p' < /proc/cmdline)

	case "$rootdev" in
	/dev/mmcblk*p*)
		mmcblk="${rootdev%p*}"
		if [ "${mmcblk##*p}" = "1" ]; then
			ab=1
		else
			ab=0
		fi
		;;
	*) #don't know how we booted, flash mmc and probe its extcsd for count
		mmcblk=/dev/mmcblk2
		if mmc extcsd read "$mmcblk" | grep -q "Boot Partition 1 enabled"; then
			ab=1
		else
			ab=0
		fi
		;;
	esac

	# override from sw-description
	rootdev=$(awk '/ATMARK_FLASH_DEV/ { print $NF }' "$TMPDIR/sw-description")
	[ -n "$rootdev" ] && mmcblk="$rootdev"
	rootdev=$(awk '/ATMARK_FLASH_AB/ { print $NF }' "$TMPDIR/sw-description")
	[ -n "$rootdev" ] && ab="$rootdev"

	echo "Using $mmcblk on boot $ab"

	# check if partitions exist and create them if not:
	# - XXX boot partitions (always exist?)
	# - XXX gpp partitions
	# sgdisk  --zap-all --new 1:20480:400M --new 2:0:400M --new 3:0:+50M --new 4:0:0 /dev/mmcblk2
}

needs_reboot() {
	[ -n "$needs_reboot" ]
}

save_vars() {
	echo "$mmcblk $ab" > "$TMPDIR/mmcblk"

	needs_reboot && touch "$TMPDIR/needs_reboot"
}

init() {
	gen_newversion

	# if no version changed, don't do anything except signaling for post
	# script. Remove file if things changed just in case.
	if cmp -s /etc/sw-versions $TMPDIR/sw-versions.merged; then
		touch "$TMPDIR/nothing_to_do"
		rm -f "$TMPDIR/sw-versions.present" "$TMPDIR/sw-versions.merged"
		exit 0
	fi
	rm -f "$TMPDIR/nothing_to_do"

	if needs_update uboot || needs_update baseos || needs_update kernel || needs_update extra_os; then
		needs_reboot=1
	fi
	cleanup_previous_upgrade
	init_rootfs
	save_vars
}

prepare_uboot() {
	local dev
	# cleanup any leftovers first
	if dev=$(readlink -e /dev/swupdate_ubootdev) && [ "${dev#/dev/loop}" != "$dev" ]; then
		losetup -d "$dev" >/dev/null 2>&1
	fi
	rm -f /dev/swupdate_ubootdev

	needs_update "uboot" || return

	if [ -e "${mmcblk}boot${ab}" ]; then
		ln -s "${mmcblk}boot${ab}" /dev/swupdate_ubootdev \
			|| error "failed to create link"
	else
		# probably sd card: prepare a loop device 32k into sd card
		# so swupdate can write directly
		# XXX racy
		ln -s "$(losetup -f)" /dev/swupdate_ubootdev \
			|| error "failed to create link"
		losetup -o $((32*1024)) -f "$mmcblk" \
			|| error "failed to setup loop device"
	fi
}

update_running_versions() {
	# atomic update for running sw versions
        mount --bind / /target || error "Could not bind mount rootfs"
        mount -o remount,rw /target || error "Could not make rootfs rw"
        "$@" < /target/etc/sw-versions > /target/etc/sw-versions.new \
                && mv /target/etc/sw-versions.new /target/etc/sw-versions
	umount /target || error "Could not umount rootfs rw copy"
}

prepare_rootfs() {
	local dev="${mmcblk}p$((ab+1))"
	local uptodate

	# Check if the current copy is up to date.
	# If there is no need to reboot, we can use it -- otherwise we need
	# to clear the flag.
	if grep -q other_rootfs_uptodate /etc/sw-versions; then
		if ! needs_reboot; then
			mount "$dev" "/target" -o ro || error "Could not mount $dev"
			return
		fi
		update_running_versions grep -v 'other_rootfs_uptodate'
	fi


	# note mkfs.ext4 fails even with -F if the filesystem is mounted
	# somewhere, so this doubles as failguard
	mkfs.ext4 -F "$dev" || error "Could not reformat $dev"
	mount "$dev" "/target" || error "Could not mount $dev"

	needs_update "base_os" && return

	# if no update is required copy current fs over
	cp -ax / /target/ || error "Could not copy existing fs over"
}

btrfs_snapshot_or_create() {
	local source="$1"
	local new="$2"

	[ -e "$basemount/$new" ] && return

	if [ -n "$source" ] &&  [ -e "$basemount/$source" ]; then
		if [ -e "$basemount/$new" ]; then
			btrfs subvolume delete "$basename/$new"
		fi
		btrfs subvolume snapshot "$basemount/$source" "$basemount/$new"
	else
		btrfs subvolume create "$basemount/$new"
	fi
}

prepare_appfs() {
	local dev="${mmcblk}p4"
	local basemount

	basemount=$(mktemp -d -t btrfs-root.XXXXXX)
	mkdir -p /target/var/app/storage /target/var/app/volumes
	mkdir -p /target/var/app/volumes_persistent /target/var/tmp

	if ! mount "$dev" "$basemount" >/dev/null 2>&1; then
		echo "Reformating $dev (app)"
		mkfs.btrfs "$dev" || error "$dev already contains another filesystem (or other mkfs error)"
		mount "$dev" "$basemount" || error "Could not mount $dev"
	fi
	btrfs_snapshot_or_create "storage_$((!ab))" "storage_${ab}" \
		|| error "Could not create storage subvol"
	btrfs_snapshot_or_create "volumes_$((!ab))" "volumes_${ab}" \
		|| error "Could not create volumes subvol"
	btrfs_snapshot_or_create "" "volumes_persistent" \
		|| error "Could not create volumes_persistent subvol"
	btrfs_snapshot_or_create "" "tmp" || error "Could not create tmp subvol"

	# wait for subvolume deletion to complete to make sure we can use
	# any reclaimed space
	btrfs subvolume sync "$basemount"
	umount "$basemount"
	rmdir "$basemount"

	mount "$dev" "/target/var/app/storage" -o "subvol=storage_${ab}" \
		|| error "Could not mount storage subvol"
	mount "$dev" "/target/var/app/volumes" -o "subvol=volumes_${ab}" \
		|| error "Could not mount volumes subvol"
	mount "$dev" "/target/var/app/volumes_persistent" -o "subvol=volumes_persistent" \
		|| error "Could not mount volumes_persistent subvol"
	mount "$dev" "/target/var/tmp" -o "subvol=tmp" \
		|| error "Could not mount tmp subvol"
}

init
prepare_uboot
prepare_rootfs
prepare_appfs
