#!/bin/sh

TMPDIR=/tmp

mmcblk=/dev/mmcblk2
ab=0
update_id=$(date +%Y%m%d_%H%M%S)

error() {
	echo "$@" >&2
	exit 1
}

get_vers() {
	local component="$1"
	local source="${2:-$TMPDIR/sw-versions.present}"

	awk '$1 == "'"$component"'" { print $2 }' < "$source"
}

gen_newversion() {
	local component oldvers newvers

	awk -F'[" ]+' '$2 == "name" {component=$4}
		component && $2 == "version" { print component, $4 }
		/,/ { component="" }' < "$TMPDIR/sw-description" \
			> "$TMPDIR/sw-versions.present"
	
	# Merge files, keeping order of original sw-versions,
	# then appending other lines from new one in order as well.
	# Could probably do better but it works and files are small..
	while read -r component oldvers; do
		newvers=$(get_vers "$component")
		echo "$component ${newvers:-$oldvers}"
	done < /etc/sw-versions > "$TMPDIR/sw-versions.merged"
	while read -r component newvers; do
		oldvers=$(get_vers "$component" /etc/sw-versions)
		[ -z "$oldvers" ] && echo "$component $newvers"
	done < "$TMPDIR/sw-versions.present" >> "$TMPDIR/sw-versions.merged"
}

need_update() {
	local component="$1"
	local newvers oldvers

	newvers=$(get_vers "$component")
	[ -n "$newvers" ] || return 1

	oldvers=$(get_vers "$component" /etc/sw-versions)
	[ "$newvers" != "$oldvers" ]
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
	# - XXX normal partitions
}

save_vars() {
	echo "${update_id}" > "$TMPDIR/update_id"
	echo "$mmcblk $ab" > "$TMPDIR/mmcblk"
}

init() {
	gen_newversion
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

	need_update "uboot" || return

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

prepare_rootfs() {
	local dev="${mmcblk}p$((ab+1))"
	# XXX cleanup unmount existing mount point

	# note mkfs.ext4 fails even with -F if the filesystem is mounted
	# somewhere, so this doubles as failguard
	mkfs.ext4 -F "$dev" || error "Could not reformat $dev"
	mount "$dev" "/target" || error "Could not mount $dev"

	need_update "base_os" && return

	# if no update is required copy current fs over
	cp -ax / /target/ || error "Could not copy existing fs over"
}

btrfs_snapshot_or_create() {
	local source="$1"
	local new="$2"

	[ -e "$basemount/$new" ] && return

	if [ -n "$source" ] &&  [ -e "$basemount/$source" ]; then
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
	btrfs_snapshot_or_create "storage" "storage_${update_id}" \
		|| error "Could not create storage subvol"
	btrfs_snapshot_or_create "volumes" "volumes_${update_id}" \
		|| error "Could not create volumes subvol"
	btrfs_snapshot_or_create "" "volumes_persistent" \
		|| error "Could not create volumes_persistent subvol"
	btrfs_snapshot_or_create "" "tmp" || error "Could not create tmp subvol"

	umount "$basemount"
	rmdir "$basemount"

	mount "$dev" "/target/var/app/storage" -o "subvol=storage_${update_id}" \
		|| error "Could not mount storage subvol"
	mount "$dev" "/target/var/app/volumes" -o "subvol=volumes_${update_id}" \
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
