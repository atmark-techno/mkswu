# SPDX-License-Identifier: MIT

error() {
	printf -- "----------------------------------------------\n" >&2
	printf -- "/!\ %s\n" "$@" >&2
	printf -- "----------------------------------------------\n" >&2

	# redefine error as no-op: this avoids looping if one of the cleanup operations fail
	error() { warning "$@"; }

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
		stdout_info echo "Command '$*' output:"
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
	return 1
}

lock_check_rebooting() {
	local unlock="$1"

	if [ -e "/tmp/.swupdate_rebooting" ]; then
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
	# tl;dr: move this lock within swupdate itself eventually or accept
	# very rare deadlocks when mixing e.g. USB and hawkbit updates after
	# failures.
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

	# busybox 'mountpoint' stats target and checks for device change, so
	# bind mounts like /var/lib/containers/overlay are not properly detected
	# as mountpoint by it.
	# util-linux mountpoint parses /proc/self/mountinfo correctly though so we
	# could use it if installed, but it is simpler to always reuse our
	# implementation instead
	! awk '$5 == "'"$dir"'" { exit 1 }' < /proc/self/mountinfo
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

	if dev=$(readlink -e /dev/swupdate_bootdev) && [ "${dev#/dev/loop}" != "$dev" ]; then
		losetup -d "$dev" >/dev/null 2>&1
	fi
	rm -f /dev/swupdate_bootdev
}

# helpers for disk encryption

luks_unlock() {
	# modifies dev if unlocked
	local target="$1"
	[ -z "$encrypted" ] && return
	[ -n "$dev" ] || error "\$dev must be set"

	if [ -e "/dev/mapper/$target" ]; then
		# already unlocked, use it
		dev="/dev/mapper/$target"
		return
	fi

	# skip if no cryptsetup
	command -v cryptsetup > /dev/null \
		|| return 0

	# not luks? nothing to do!
	cryptsetup isLuks "$dev" \
		|| return 0

	command -v caam-decrypt > /dev/null \
		|| return 0

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
		|| return 0

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


needs_reboot() {
	[ -n "$needs_reboot" ]
}

update_rootfs() {
	[ -n "$update_rootfs" ]
}

update_baseos() {
	[ "$update_rootfs" = "baseos" ]
}

mkswu_var() {
	local BASEOS_CONF="${BASEOS_CONF:-/etc/atmark/baseos.conf}"
	local var="$1"
	local val

	# env var > desc file > baseos.conf
	val=$(eval "echo \"\$$var\"")
	if [ -n "$val" ]; then
		echo "$val"
		return
	fi

	if val=$(grep -F "# MKSWU_$var " "$SWDESC"); then
		echo "$val" | sed -e "s/ *# MKSWU_$var //"
		return
	fi

	if [ -e "$BASEOS_CONF" ]; then
		val=$(. "$BASEOS_CONF"; eval "echo \"\$MKSWU_$var\"")
		echo "$val"
	fi
}

post_action() {
	# note this is in a subshell so caching only works if the caller
	# assigns the variable
	if [ -n "$POST_ACTION" ]; then
		echo "$POST_ACTION"
		return
	fi

	POST_ACTION=$(mkswu_var POST_ACTION)
	# container only works if no reboot
	if [ "$POST_ACTION" = "container" ] && needs_reboot; then
		POST_ACTION=""
	fi
	echo "$POST_ACTION"
}


cleanup() {
	remove_bootdev_link
	umount_if_mountpoint /target || error "Could not umount $dir"
	luks_close_target
}

init_common() {
	if [ -e "$TMPDIR/sw-description" ]; then
		SWDESC="$TMPDIR/sw-description"
	elif [ -e "/var/tmp/sw-description" ]; then
		SWDESC="/var/tmp/sw-description"
	elif [ -e "/tmp/sw-description" ]; then
		SWDESC="/tmp/sw-description"
	else
		error "sw-description not found!"
	fi

	# debug tests
	grep -q "DEBUG_SKIP_SCRIPTS" "$SWDESC" && exit 0

	true
}

init_common
