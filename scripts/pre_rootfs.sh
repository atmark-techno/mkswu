copy_to_target() {
	local file
	local dir

	for file; do
		# source file must exist... being careful of symlinks
		[ -L "$fsroot$file" ] || [ -e "$fsroot$file" ] || continue
		# and destination file not (probably already copied)
		# except directories which we'll copy into with no-cobbler
		[ -e "$TARGET/$file" ] && [ ! -d "$TARGET/$file" ] && continue
		[ -L "$TARGET/$file" ] && continue

		dir="${file%/*}"
		mkdir_p_target "$dir"
		cp -aTu "$fsroot$file" "$TARGET/$file" \
			|| error "Failed to copy $file from previous rootfs"
	done
}

update_preserve_list() {
	local preserve_version=0 max_version=14
	local TARGET="${TARGET:-/target}"
	local list="$TARGET/etc/swupdate_preserve_files"

	if [ -e "/etc/swupdate_preserve_files" ]; then
		cp /etc/swupdate_preserve_files "$list" \
			|| error "Could not copy swupdate_preserve_files over"
		preserve_version=$(awk '/^PRESERVE_FILES_VERSION/ { print $2; exit }' \
					"$list" 2>/dev/null)

		# assume anything invalid (non-digit) is 0
		case "$preserve_version" in
		*[!0-9]*|"") preserve_version=0;;
		esac
	fi

	[ "$preserve_version" -ge "$max_version" ] && return

	if [ -e "$list" ] && grep -qE '^PRESERVE_FILES_VERSION' "$list"; then
		sed -i -e "s/^\(PRESERVE_FILES_VERSION\).*/\1 $max_version/" "$list" \
			|| error "Could not update $list"
	else
		cat >> "$list" <<EOF || error "Could not update $list"
### Files listed here will be copied over when rootfs is updated
### You can freely add or remove files from the list, removed
### entries will not be added back as long as the below line is
### kept intact. Do not remove or change!
PRESERVE_FILES_VERSION $max_version

# file can be prefixed with POST to be copied after rootfs is
# extracted, e.g.
#POST /boot
# would preserve the installed kernel without rebuilding a custom
# image if uncommented (destination is removed before copy)
EOF
	fi

	if [ "$preserve_version" -le 0 ]; then
		cat >> "$list" <<EOF || error "Could not update $list"

# v1 list: base files, swupdate, ssh and network config
/etc/atmark
/etc/fstab
/etc/motd
/etc/conf.d/overlayfs
/etc/swupdate_preserve_files

/etc/hwrevision
/etc/swupdate.cfg
/etc/swupdate.pem
/etc/swupdate.aes-key
/etc/runlevels/default/swupdate-hawkbit
/etc/conf.d/swupdate-hawkbit
/etc/runlevels/default/swupdate-url
/etc/conf.d/swupdate-url
/etc/swupdate.watch

/etc/runlevels/default/sshd
/etc/ssh
/root/.ssh
/home/atmark/.ssh

/etc/hostname
/etc/network
/etc/resolv.conf
/etc/NetworkManager/system-connections
EOF
	fi
	if [ "$preserve_version" -le 1 ]; then
		cat >> "$list" << EOF || error "Could not update $list"

# v2 list: dtb symlink, ca-certificates, local.d
/boot/armadillo.dtb
/usr/local/share/ca-certificates
/etc/local.d
EOF
	fi
	if [ "$preserve_version" -le 2 ]; then
		cat >> "$list" << EOF || error "Could not update $list"

# v3 list: DTS overlay, LTE extension board support
/boot/overlays.txt
/etc/runlevels/default/modemmanager
/etc/runlevels/default/connection-recover
EOF
	fi
	if [ "$preserve_version" -le 3 ]; then
		cat >> "$list" << EOF || error "Could not update $list"

# v4 list: iptables, some /etc/x.d directories
/etc/dnsmasq.d
/etc/sysctl.d
/etc/hostapd/hostapd.conf
/etc/runlevels/default/hostapd
/etc/iptables/rules-save
/etc/iptables/rules6-save
/etc/runlevels/default/iptables
/etc/runlevels/default/ip6tables
EOF
	fi
	if [ "$preserve_version" -le 4 ]; then
		cat >> "$list" << EOF || error "Could not update $list"

# v5 list: uboot env, machine-id
/boot/uboot_env.d
/etc/machine-id
EOF
	fi

	if [ "$preserve_version" -le 5 ]; then
		cat >> "$list" << EOF || error "Could not update $list"

# v6 list: g4/a6e LTE/wifi extension board support, atmark conf.d files
/etc/runlevels/boot/modemmanager
/etc/runlevels/boot/ems31-boot
/etc/runlevels/default/wwan-led
/etc/runlevels/shutdown/wwan-safe-poweroff
/etc/runlevels/default/wifi-recover
POST /etc/conf.d/wifi-recover
POST /etc/conf.d/podman-atmark
EOF
	fi
	if [ "$preserve_version" -le 6 ]; then
		cat >> "$list" << EOF || error "Could not update $list"

# v7 list: a6e power-utils files
/etc/containers/aiot_gw_container_hooks.d
EOF
	fi
	if [ "$preserve_version" -le 7 ]; then
		cat >> "$list" << EOF || error "Could not update $list"

# v8 list: udev rules
/etc/udev/rules.d
EOF
	fi
	if [ "$preserve_version" -le 8 ]; then
		cat >> "$list" << EOF || error "Could not update $list"

# v9 list: avahi service
/etc/runlevels/default/avahi-daemon
EOF
	fi
	if [ "$preserve_version" -le 9 ]; then
		cat >> "$list" << EOF || error "Could not update $list"

# v10 list: chown abos-web directory
CHOWN abos-web-admin: /etc/atmark/abos_web
EOF
	fi

	if [ "$preserve_version" -le 10 ]; then
		cat >> "$list" << EOF || error "Could not update $list"

# v11 list: chrony config
/etc/chrony/conf.d
EOF
	fi

	if [ "$preserve_version" -le 11 ]; then
		cat >> "$list" << EOF || error "Could not update $list"

# v12 list: timezone settings/twin agent enable state
/etc/localtime
/etc/zoneinfo
/etc/runlevels/default/armadillo-twin-agentd
EOF
	fi

	if [ "$preserve_version" -le 12 ]; then
		cat >> "$list" << EOF || error "Could not update $list"

# v13 list: syslog service config
/etc/conf.d/syslog
EOF
	fi

	if [ "$preserve_version" -le 13 ]; then
		cat >> "$list" << EOF || error "Could not update $list"

# v14 list
/etc/runlevels/boot/sim7672-boot
EOF
	fi
}

copy_preserve_files() {
	local f
	local TARGET="${TARGET:-/target}"
	local IFS='
'
	grep -E '^/' "$TARGET/etc/swupdate_preserve_files" \
		| sort -u > "$MKSWU_TMP/preserve_files_pre"
	while read -r f; do
		# shellcheck disable=SC2086 # No quote to expand globs
		copy_to_target $f
	done < "$MKSWU_TMP/preserve_files_pre"

	rm -f "$MKSWU_TMP/preserve_files_pre"
}

# mount helper for rootfs
mount_rootfs_btrfs() {
	mount -t btrfs -o compress-force=zstd,discard=async,noatime \
		"$src" "$dst" >/dev/null 2>&1
}

mount_rootfs_ext4() {
	mount -t ext4 -o noatime "$src" "$dst" >/dev/null 2>&1
}

mount_rootfs() {
	local src="$1" dst="$2" hint_fstype="${3-}"

	[ -n "$hint_fstype" ] \
		|| hint_fstype="$(findmnt -nr -o FSTYPE "${fsroot:-/live/rootfs}")" \
		|| error "Could not get rootfs fstype"

	case "$hint_fstype" in
	btrfs)
		mount_rootfs_btrfs || mount_rootfs_ext4
		;;
	ext4)
		mount_rootfs_ext4 || mount_rootfs_btrfs
		;;
	*)
		error "Unsupported filesystem for rootfs: $hint_fstype"
		;;
	esac
}

cp_one_fs() {
	local source="$1"

	# shellcheck disable=SC2016 ## single quotes on purpose...
	unshare -m sh -c 'mount --bind "$1" /mnt && cp -a /mnt/. /target/' \
		-- "$source" || error "Could not copy $source to target"
}

mount_target_rootfs() {
	local dev="${partdev}$((ab+1))"
	local extlinux="" encrypted="" fstype=""

	# support older version of overlayfs
	local fsroot=/live/rootfs/
	[ -e "$fsroot" ] || fsroot="/"

	# check encryption of the current partition (and not target's)
	cryptsetup isLuks "${partdev}$((!ab+1))" >/dev/null 2>&1 && encrypted=1

	if [ -n "$(mkswu_var ENCRYPT_ROOTFS)" ]; then
		[ -n "$(get_version "boot_linux")" ] \
			|| error "encrypting rootfs requires having swdesc_boot_linux installed"
		# We want to bump timestamp if we didn't have encryption before
		# note we don't care about preserving this for post scripts
		if [ -z "$encrypted" ] && [ -z "$update_rootfs" ]; then
			update_rootfs=1
		fi
		encrypted=1
	fi

	# We need /target to exist for update, try hard to create it
	# Note:
	# - we need a known path because that path is used in sw-description
	#   for archives as well as post scripts
	# - we want a path regular users can't hijack e.g. not /tmp or similar
	# - it should almost always already exist, as created for next update
	if ! [ -d /target ]; then
		[ -e /target ] && error "/target exists but is not a directory, update failing"
		if ! mkdir /target 2>/dev/null; then
			local tmp fail=""
			# read-only filesystem, remount somewhere else as rw
			# to not impact current fs
			tmp=$(mktemp -d) \
			    && mount --bind / "$tmp" \
			    && mount -o remount,rw - "$tmp" \
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
	# If there is no base_os update we can use it.
	if [ -n "$upgrade_available" ] \
	    && ! needs_update "base_os" \
	    && luks_unlock "rootfs_$ab" \
	    && mount_rootfs "$dev" /target; then
		if [ ! -e /target/.created ] \
		    && [ -s /etc/.rootfs_update_timestamp ] \
		    && cmp -s /etc/.rootfs_update_timestamp /target/etc/.rootfs_update_timestamp; then
			info "Other fs up to date, skipping copy"
			return
		fi
		umount "/target"
	fi

	if [ -n "$encrypted" ]; then
		dev="${partdev}$((ab+1))"
		luks_close_target
		luks_format "rootfs_$ab"
	fi

	fstype=$(mkswu_var ROOTFS_FSTYPE)
	[ -n "$fstype" ] || fstype=$(findmnt -nr -o FSTYPE /live/rootfs 2>/dev/null)
	[ -n "$fstype" ] || fstype=btrfs
	# extlinux requires... ext filesystem, override any setting.
	[ -e "/boot/extlinux.conf" ] && extlinux=1 && fstype=ext4
	case "$fstype" in
	btrfs)
		mkfs.btrfs -q -L "rootfs_${ab}" -m dup -f "$dev" \
			|| error "Could not reformat $dev"
		;;
	ext4)
		mkfs.ext4 -q ${extlinux:+-O "^64bit"} -L "rootfs_${ab}" -F "$dev" \
			|| error "Could not reformat $dev"
		;;
	*)
		error "Unexpected fstype for rootfs: $fstype. Must be ext4 or btrfs"
	esac
	mount_rootfs "$dev" "/target" "$fstype"

	mkdir -p /target/boot /target/mnt /target/target
	touch /target/.created

	if needs_update "base_os"; then
		mkdir_p_target /etc
		if [ -n "$(mkswu_var NO_PRESERVE_FILES)" ]; then
			info "Updating base os (without swupdate_preserve_files)"
			return
		fi
		info "Updating base os: copying swupdate_preserve_files"
		update_preserve_list
		copy_preserve_files
		return
	fi

	# if no update is required copy current fs over
	info "No base os update: copying current os over"


	if [ -e "/live/rootfs" ]; then
		cp_one_fs /live/rootfs
	else
		# support older version of overlayfs
		cp_one_fs /
	fi
}

prepare_rootfs() {
	mount_target_rootfs
	if update_rootfs; then
		# we won't be able to reuse the fs again, do this
		# now in case of error
		update_rootfs_timestamp
	fi
	if [ -n "$(mkswu_var CONTAINER_CLEAR)" ]; then
		rm -f /target/etc/atmark/containers/*.conf
	fi
	# mount tmpfs in /target/tmp for scripts that might want to use /tmp
	[ -d /target/tmp ] || mkdir /target/tmp
	mount -t tmpfs tmpfs /target/tmp \
		|| error "Could not mount tmpfs on target's /tmp"
}

[ -n "$TEST_SCRIPTS" ] && return

prepare_rootfs
