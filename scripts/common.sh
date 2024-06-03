# SPDX-License-Identifier: MIT

error() {
	printf -- "----------------------------------------------\n" >&2
	printf -- "/!\ %s\n" "$@" >&2
	printf -- "----------------------------------------------\n" >&2

	# redefine error as no-op: this avoids looping if one of the cleanup operations fail
	error() { warning "$@"; }
	# also mark we're in error for cleanup (container restart check)
	in_error=1

	cleanup
	if [ -n "$soft_fail" ]; then
		echo "An error happened after changes have been applied" >&2
		echo "Rebooting to finish applying anything left" >&2
		reboot
	fi
	unlock_update
	exit 1
}

warning() {
	stdout_warn printf -- "----------------------------------------------\n"
	stdout_warn printf -- "WARNING: %s\n" "$@"
	stdout_warn printf -- "----------------------------------------------\n"
}

info() {
	stdout_info printf -- "%s\n" "$@"
}

# adjust podman outputs: podman sometimes lists containers ids
# and it's not clear what they correspond to without a wrapper
podman_info() {
	info_if_not_empty command podman "$@"
}

podman_list_images() {
	local store="/target/var/lib/containers/storage_readonly"
	# shellcheck disable=SC2016 # (don't expand dollars)
	local format='{{$id := .Id}}{{range .Names}}{{$id}} {{.}}{{println}}{{end}}{{.Id}}'
	# temporary podman root cannot be in overlayfs due to podman
	# restrictions (in particular /tmp would not work), so use /run
	local tmproot="/run/podman_empty_root"
	[ -e "$tmproot" ] && rm -rf "$tmproot"

	podman image list --root "$tmproot" \
			--storage-opt additionalimagestore="$store" \
			--format "$format" \
		|| error "Could not list container images"
	rm -rf "$tmproot"
}


fw_setenv_nowarn() {
	FILTER="Cannot read environment, using default|Environment WRONG|Environment OK" \
		info_if_not_empty command fw_setenv "$@"
}

# options:
# FILTER: run grep -vE on filter and only print non-matches
# NOSTDOUT: drop stdout and only consider stderr (for openssl cms-verify)
info_if_not_empty() {
	local output="$MKSWU_TMP/cmd_output"
	local ret

	if [ -n "$NOSTDOUT" ]; then
		"$@" 2> "$output" >/dev/null
	else
		"$@" > "$output" 2>&1
	fi
	ret=$?

	if [ -n "$FILTER" ]; then
		# can't check for grep error redirecting file as it returns
		# non-zero if no match... hopefully mv will fail then?
		grep -vE "$FILTER" < "$output" > "$output.filter"
		if ! mv "$output.filter" "$output"; then
			echo "Could not filter '$*' output" >&2
			ret=1
		fi
	fi

	if [ -s "$output" ]; then
		info "Command '$*' output:"
		stdout_info cat "$output"
	fi
	rm -f "$output"
	return "$ret"
}

stdout_warn() {
	# we hardcode fd values here to avoid eval of message,
	# which brings in painful quoting problems.
	# Just keep using stderr on unexpected value.
	case "$SWUPDATE_WARN_FD" in
	4) "$@" >&4;;
	*) "$@" >&2;;
	esac
}

stderr_warn() {
	case "$SWUPDATE_WARN_FD" in
	4) "$@" 2>&4;;
	*) "$@";;
	esac
}

stdout_info() {
	# this one keeps stdout if unset
	case "$SWUPDATE_INFO_FD" in
	3) "$@" >&3;;
	*) "$@";;
	esac
}

stdout_info_or_error() {
	case "$SWUPDATE_INFO_FD" in
	3) "$@" >&3;;
	*) "$@" >&2;;
	esac
}

stderr_info() {
	case "$SWUPDATE_INFO_FD" in
	3) "$@" 2>&3;;
	*) "$@";;
	esac
}

is_locked() {
	[ "$(cat /tmp/.swupdate_lock/pid 2>/dev/null)" = "$PPID" ]
}

try_lock() {
	local pid

	lock_check_rebooting

	if mkdir /tmp/.swupdate_lock 2>/dev/null; then
		echo $PPID > /tmp/.swupdate_lock/pid
		return 0
	fi

	if [ -e /tmp/.swupdate_lock ]; then
		# there is a small window where directory exists but not pid file
		# cheat around it with a sleep...
		[ -e /tmp/.swupdate_lock/pid ] || sleep 1

		if ! pid=$(cat /tmp/.swupdate_lock/pid 2>/dev/null); then
			rm -rf /tmp/.swupdate_lock
			try_lock
			return
		fi
		[ "$pid" = "$PPID" ] && return 0
		if [ "$(cat "/proc/$pid/comm" 2>/dev/null)" != swupdate ]; then
			rm -rf /tmp/.swupdate_lock
			try_lock
			return
		fi
	else
		# mkdir failed but lock does not exist, we could have been
		# raced so try again once without masking stderr and if it
		# still does not exist error out...
		if mkdir /tmp/.swupdate_lock; then
			echo $PPID > /tmp/.swupdate_lock/pid
			return 0
		fi

		[ -e /tmp/.swupdate_lock ] \
			|| error "Could not create our script install lock, aborting"
	fi

	# for /tmp, we need to check it's root owned to avoid denial of service
	# if stat failed, directory didn't exist and other might be unlocking,
	# retry will work
	local owner
	if owner="$(stat -c %u /tmp/.swupdate_lock 2>/dev/null)" && [ "$owner" != "0" ]; then
		rm -rf "/tmp/.swupdate_lock"
		try_lock
		return
	fi

	return 1
}

lock_check_rebooting() {
	local unlock="$1"

	if [ -e "/run/swupdate_rebooting" ]; then
		if [ -n "$unlock" ]; then
			unlock_update
		fi
		error "reboot in progress!!"
	fi

}

lock_update() {
	# lock handling necessary for hawkbit/usb/manual install locking
	# we cannot just use flock here as this shell script will exit before
	# the end of the install, and we cannot use a simple 'mkdir lock'
	# either because no cleanup is reliable if the update process gets
	# killed, so rely on the parent's PID being a swupdate process:
	# - if the update runs normally it will clear the lock as appropriate
	# (error in script or post script)
	# - if the whole swupdate process is killed (e.g. ^C) then the pid will
	# not exist or hopefully not be swupdate again (PID recycling) and lock
	# will be freed, but that should hopefully be rare enough..
	# - if update fails between pre/post or the script gets killed abruptly
	# without killing swupdate, then we -also- detect if the swupdate pid
	# is our own parent and keep the existing lock
	# - that leaves a deadlock if an update failed without unlocking in
	# another swupdate process, but hopefully most users will only use a
	# single update vector? and even if they use multiple this should not
	# happen unless the updates are bogus.
	#
	# This lock is now redundant with the lock taken in swupdate itself:
	# it is kept for backwards compatibility.
	# In 2024/07, it will only be created if SWUPDATE_VERSION is not set
	# (swupdate < 2023.12)
	if try_lock; then
		# recheck for reboot after we've locked in case of race.
		lock_check_rebooting unlock
		return
	fi
	stdout_warn echo "/tmp/.swupdate_lock exists: another update in progress? Waiting until it disappears"

	while ! try_lock; do
		sleep 5;
	done
	lock_check_rebooting unlock
}

unlock_update() {
	rm -rf /tmp/.swupdate_lock
}

mkdir_p_target() {
	local dir="$1" parent ownermode
	local TARGET="${TARGET:-/target}"

	# nothing to do if target exists or source doesn't
	[ -e "$TARGET/$dir" ] && return
	ownermode=$(stat -c "%u:%g %a" "$dir" 2>/dev/null) \
		|| return

	parent="${dir%/*}"
	[ -n "$parent" ] && mkdir_p_target "$parent"

	mkdir "$TARGET/$dir" \
		|| error "Could not create $TARGET/$dir"

	chown "${ownermode% *}" "$TARGET/$dir" \
		|| error "Could not chown $dir"
	chmod "${ownermode#* }" "$TARGET/$dir" \
		|| error "Could not chmod $dir"
	touch -r "$dir" "$TARGET/$dir" \
		|| error "Could set $dir timestamp"
}

is_mountpoint() {
	local dir="$1"
	local tid="${2:-self}"

	# busybox 'mountpoint' stats target and checks for device change, so
	# bind mounts like /var/lib/containers/overlay are not properly detected
	# as mountpoint by it.
	# util-linux mountpoint parses /proc/self/mountinfo correctly though so we
	# could use it if installed, but it is simpler to always reuse our
	# implementation instead, which also allows checking other namespaces
	! awk -v dir="$dir" '$5 == dir { exit 1 }' < "/proc/$tid/mountinfo"
}

umount_if_mountpoint() {
	local dir="$1"

	# nothing to do if not a mountpoint
	is_mountpoint "$dir" || return 0

	# findmnt outputs in tree order, so umounting from
	# last line first should always work
	findmnt -nr -o TARGET -R "$dir" | tac | xargs -r umount --
}

remove_bootdev_link() {
	local dev

	if dev=$(readlink /dev/swupdate_bootdev) && [ -e "$dev" ] \
	    && [ "${dev#/dev/loop}" != "$dev" ]; then
		losetup -d "$dev" >/dev/null 2>&1
	fi
	rm -f /dev/swupdate_bootdev
}

# helpers for disk encryption

luks_unlock() {
	# modifies dev if unlocked
	local target="$1"
	[ -z "$encrypted" ] && return 0
	[ -n "$dev" ] || error "\$dev must be set"

	if [ -e "/dev/mapper/$target" ]; then
		# already unlocked, use it
		dev="/dev/mapper/$target"
		return 0
	fi

	# skip if no cryptsetup
	command -v cryptsetup > /dev/null \
		|| return 1

	# 'encrypted' was set, but not luks?
	cryptsetup isLuks "$dev" \
		|| return 1

	command -v caam-decrypt > /dev/null \
		|| return 1

	local index offset
	case "$dev" in
	*mmcblk*p*)
		# keys are stored in $rootdev as follow
		# 0MB        <GPT header and partition table>
		# 9MB        key for part 1
		# 9MB+4k     key for part 2
		# 9MB+(n*4k) key for part n+1
		# 10MB       first partition
		index=${dev##*p}
		index=$((index-1))
		offset="$(((9*1024 + index*4)*1024))"
		;;
	*) error "LUKS only supported on mmcblk*p* partitions" ;;
	esac

	mkdir -p /run/caam
	local KEYFILE=/run/caam/lukskey
	# use unshared tmpfs to not leak key too much
	# key is:
	# - 112 bytes of caam black key
	# - 16 bytes of iv followed by rest of key
	unshare -m sh -c "mount -t tmpfs tmpfs /run/caam \
		&& dd if=$rootdev of=$KEYFILE.mmc bs=4k count=1 status=none \
			iflag=skip_bytes skip=$offset \
		&& dd if=$KEYFILE.mmc of=$KEYFILE.bb bs=112 count=1 status=none \
		&& dd if=$KEYFILE.mmc of=$KEYFILE.enc bs=4k status=none \
			iflag=skip_bytes skip=112 \
		&& caam-decrypt $KEYFILE.bb AES-256-CBC $KEYFILE.enc \
			$KEYFILE.luks >/dev/null 2>&1 \
		&& cryptsetup luksOpen --key-file $KEYFILE.luks \
			--allow-discards $dev $target >/dev/null 2>&1" \
		|| return

	dev="/dev/mapper/$target"
}

luks_format() {
	# modifies dev with new target
	local target="$1"
	[ -n "$dev" ] || error "\$dev must be set"

	command -v cryptsetup > /dev/null \
		|| error "cryptsetup must be installed in current rootfs"
	command -v caam-decrypt > /dev/null \
		|| error "caam-decrypt must be installed in current rootfs"

	local index offset
	case "$dev" in
	*mmcblk*p*)
		index=${dev##*p}
		index=$((index-1))
		offset="$(((9*1024 + index*4)*1024))"
		;;
	*) error "LUKS only supported on mmcblk*p* partitions" ;;
	esac

	mkdir -p /run/caam
	local KEYFILE=/run/caam/lukskey
	# lower iter-time to speed PBKDF phase up,
	# since our key is random PBKDF does not help
	# also, we don't need a 16MB header so make it as small as possible (1MB)
	# by limiting the maximum number of luks keys (3 here, same size with less)
	# key size is 112
	unshare -m sh -c "mount -t tmpfs tmpfs /run/caam \
		&& caam-keygen create ${KEYFILE##*/} ccm -s 32 \
		&& dd if=/dev/random of=$KEYFILE.luks bs=$((4096-112-16)) count=1 status=none \
		&& dd if=/dev/random of=$KEYFILE.iv bs=16 count=1 status=none \
		&& cat $KEYFILE.iv $KEYFILE.luks > $KEYFILE.toenc \
		&& caam-encrypt $KEYFILE.bb AES-256-CBC $KEYFILE.toenc $KEYFILE.enc \
		&& cat $KEYFILE.bb $KEYFILE.iv $KEYFILE.enc > $KEYFILE.mmc \
		&& { if ! [ \$(stat -c %s $KEYFILE.mmc) = 4096 ]; then \
			echo \"Bad key size \$(stat -c %s $KEYFILE.mmc)\"; false; \
		fi; } \
		&& cryptsetup luksFormat -q --key-file $KEYFILE.luks \
			--pbkdf pbkdf2 --iter-time 1 \
			--luks2-keyslots-size=768k \
			$dev > /dev/null \
		&& cryptsetup luksOpen --key-file $KEYFILE.luks \
			--allow-discards $dev $target \
		&& dd if=$KEYFILE.mmc of=$rootdev bs=4k count=1 status=none \
			oflag=seek_bytes seek=$offset" \
		|| error "Could not create luks partition on $dev"

	dev="/dev/mapper/$target"
}

luks_close_target() {
	[ -n "$ab" ] || return
	cryptsetup luksClose "rootfs_$ab" >/dev/null 2>&1
}

get_mmc_name() {
	cat "/sys/class/block/${rootdev#/dev/}/device/name" 2>/dev/null
}

needs_reboot() {
	# if we're in an error, we'll reboot if soft_fail is set
	if [ -n "$in_error" ]; then
		[ -n "$soft_fail" ]
		return
	fi
	[ -n "$needs_reboot" ]
}

update_rootfs() {
	[ -n "$update_rootfs" ]
}

update_baseos() {
	[ "$update_rootfs" = "baseos" ]
}

update_rootfs_timestamp() {
	date +%s > /target/etc/.rootfs_update_timestamp \
		|| error "Could not update rootfs timestamp"
	# in the unlikely chance we somehow got the same date, add something...
	if cmp -s /etc/.rootfs_update_timestamp /target/etc/.rootfs_update_timestamp; then
		echo "(differentiator for identical timestamps)" \
				>> /target/etc/.rootfs_update_timestamp \
			|| error "Could not update rootfs timestamp"
	fi
}

mkswu_var() {
	local BASEOS_CONF="${BASEOS_CONF:-/etc/atmark/baseos.conf}"
	local var="$1"
	local val

	# env var > desc file > baseos.conf
	val=$(eval "echo \"\$MKSWU_$var\"")
	if [ -n "$val" ]; then
		echo "$val"
		return
	fi

	if val=$(grep -F "# MKSWU_$var " "$SWDESC"); then
		# shellcheck disable=SC2001 # can't use simple replacement here for multiline
		echo "$val" | sed -e "s/ *# MKSWU_$var //"
		return
	fi

	if [ -e "$BASEOS_CONF" ]; then
		val=$(. "$BASEOS_CONF"; eval "echo \"\$MKSWU_$var\"")
		echo "$val"
	fi
}

set_post_action() {
	post_action=$(mkswu_var POST_ACTION)
	# container only works if no reboot
	if [ "$post_action" = "container" ] && needs_reboot; then
		post_action=""
	fi
}

clear_b_side() {
	# free up appfs space after update failure
	# (we could rollback-clone, but that's best left up to users to re-do on
	# next boot if required)

	# if /target isn't mounted then B side wasn't touched yet
	if ! is_mountpoint /target; then
		return
	fi

	# might be unset if called from cleanup
	if [ -z "$ab" ]; then
		ab="$(cat "$MKSWU_TMP/ab" 2> /dev/null)" \
			|| return
	fi

	# remove snapshots
	appdev=$(findmnt -nr --nofsroot -o SOURCE /var/tmp)
	[ -n "$appdev" ] || return
	if is_mountpoint /target/mnt; then
		umount /target/mnt || return
	fi
	mount -t btrfs "$appdev" /target/mnt || return
	if [ -e "/target/mnt/boot_$ab/volumes" ]; then
		btrfs subvol delete "/target/mnt/boot_$ab/volumes"
	fi
	if [ -e "/target/mnt/boot_$ab/containers_storage" ]; then
		btrfs subvol delete "/target/mnt/boot_$ab/containers_storage"
	fi
	umount /target/mnt
}

cleanup() {
	local status="$1"

	if [ "$status" != success ]; then
		clear_b_side
	fi
	remove_bootdev_link
	if is_mountpoint "/target/var/tmp"; then
		# cannot delete a subvolume by its mount point directly: use id
		# - `subvol list` prints something ID 123 gen 456 top level 789 path foo/bar
		# - match updates_tmp volume
		# - it shouldn't have any subvolume but tac/loop just in case
		btrfs subvol list /target/var/tmp \
			| grep -F 'path updates_tmp' \
			| tac \
			| while read -r _ id _; do
				btrfs subvol delete -i "$id" /target/var/tmp;
			done
	fi
	umount_if_mountpoint /target || error "Could not umount $dir"
	luks_close_target
	if [ -e "$MKSWU_TMP/podman_containers_killed" ] && ! needs_reboot; then
		info "Restarting containers"
		podman_start -a
	fi
}

clear_internal_variables() {
	# these variables should be set before calling this
	#     TMPDIR MKSWU_TMP SCRIPTSDIR
	# these variables should always be set before use
	#     rootdev partdev ab post_action
	# these variables are used accross scripts and should not depend on env
	unset needs_reboot update_rootfs upgrade_available
	unset FILTER NOSTDOUT
	# these variables are used for tests, but should not be used when
	# invoking mkswu externally
	unset CONTAINER_CONF_DIR TARGET SWUPDATE_PEM
	unset PASSWD NPASSWD SHADOW NSHADOW GROUP NGROUP
	unset system_versions BASEOS_CONF TEST_SCRIPTS
	# This comment describes variables that can currently be used
	# to override something, but might be subject to change.
	# these variables are allowed through mkswu_var:
	#     MKSWU_ALLOW_EMPTY_LOGIN MKSWU_ALLOW_PUBLIC_CERT
	#     MKSWU_CONTAINER_CLEAR MKSWU_ENCRYPT_ROOTFS MKSWU_ENCRYPT_USERFS MKSWU_FORCE_VERSION
	#     MKSWU_NOTIFY_FAIL_CMD MKSWU_NOTIFY_STARTING_CMD MKSWU_NOTIFY_SUCCESS_CMD
	#     MKSWU_NO_ARCH_CHECK MKSWU_NO_PRESERVE_FILES MKSWU_POST_ACTION
	#     MKSWU_ROOTFS_FSTYPE MKSWU_SKIP_APP_SUBVOL_SYNC
	# these are used directly:
	#     SW_ROLLBACK_ALLOWED SWUPDATE_FROM_INSTALLER
	#     SWUPDATE_HAWKBIT SWUPDATE_USB_SWU SWUPDATE_ARMADILLO_TWIN
	#     CONTAINER_CONF/CONTAINER_STORAGE_CONF/CONTAINERS_REGISTRIES_CONF
	# these come from swupdate
	#     SWUDPATE_WARN_FD SWUPDATE_INFO_FD
}

init_common() {
	clear_internal_variables

	if [ -e "$TMPDIR/sw-description" ]; then
		SWDESC="$TMPDIR/sw-description"
	elif [ -e "/var/tmp/sw-description" ]; then
		SWDESC="/var/tmp/sw-description"
	elif [ -e "/tmp/sw-description" ]; then
		SWDESC="/tmp/sw-description"
	else
		error "sw-description not found!"
	fi

	# debug tests... or swupdate overriding this in favor of ABOS scripts
	grep -q "DEBUG_SKIP_SCRIPTS" "$SWDESC" && exit 0

	true
}

init_common
