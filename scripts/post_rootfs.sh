update_shadow_user() {
	local user="$1"
	local oldpass

	oldpass=$(awk -F':' '$1 == "'"$user"'" && $3 != "0"' "$SHADOW" \
			| sed -e 's/[\\:&]/\\&/g')
	# password was never set: skip
	[ -n "$oldpass" ] || return
	# password already set on target: also skip
	grep -qE "^$user:[^!:]" "$NSHADOW" && return

	if grep -qE "^$user:" "$NSHADOW"; then
		sed -i -e 's:^'"$user"'\:.*:'"$oldpass"':' "$NSHADOW"
	else
		echo "$oldpass" | sed -e 's/\\\([\\:&]\)/\1/g' >> "$NSHADOW"
	fi || error "Could not update shadow for $user"
}

update_user_groups() {
	local user="$1"
	local group

	awk -F: '$4 ~ /(,|^)'"$user"'(,|$)/ { print $1 }' < "$GROUP" |
		while read -r group; do
			# already set
			grep -qE "^$group:.*[:,]$user(,|$)" "$NGROUP" \
				&& continue

			if grep -qE "^$group:.*:$" "$NGROUP"; then
				sed -i -e 's/^'"$group"':.*:/&'"$user"'/' "$NGROUP"
			else
				sed -i -e 's/^'"$group"':.*/&,'"$user"'/' "$NGROUP"
			fi || error "Could not update group $group / $user"
		done
}

update_shadow() {
	local user group
	# test constants
	local PASSWD="${PASSWD:-$fsroot/etc/passwd}"
	local NPASSWD="${NPASSWD:-/target/etc/passwd}"
	local SHADOW="${SHADOW:-$fsroot/etc/shadow}"
	local NSHADOW="${NSHADOW:-/target/etc/shadow}"
	local GROUP="${GROUP:-$fsroot/etc/group}"
	local NGROUP="${NGROUP:-/target/etc/group}"

	# "$PASSWD", group and shadow have to be part of rootfs as
	# rootfs updates can change system users, but we want to keep
	# "real" users as well so copy them over manually:
	# - copy non-existing "real" groups (gid >= 1000)
	# - for each real user (root, abos* or uid >= 1000), copy its password
	# if the old one not set and add it to groups it had been added to
	awk -F: '$3 >= 1000 && $3 < 65500 { print $1 }' < "$GROUP" |
		while read -r group; do
			grep -qE "^$group:" "$NGROUP" \
				|| grep -E "^$group:" "$GROUP" >> "$NGROUP" \
				|| return
		done

	awk -F: '$1 == "root" || $1 ~ /^abos/ \
			|| ( $3 >= 1000 && $3 < 65500 ) {
				print $1
			}' < "$PASSWD" |
		while read -r user; do
			grep -qE "^$user:" "$NPASSWD" \
				|| grep -E "^$user:" "$PASSWD" >> "$NPASSWD" \
				|| return
			update_shadow_user "$user"
			update_user_groups "$user"
		done
}

update_running_versions() {
	cp "$1" /etc/sw-versions || error "Could not update /etc/sw-versions"

	[ "$(findmnt -nr -o FSTYPE -T /etc/sw-versions)" = "overlay" ] || return

	# bind-mount / somewhere else to write below it as well
	mount --bind "$fsroot" /target || error "Could not bind mount rootfs"
	mount -o remount,rw - /target || error "Could not make rootfs rw"
	cp /etc/sw-versions /target/etc/sw-versions \
		|| error "Could not write $1 to /etc/sw-versions"
	umount /target || error "Could not umount rootfs rw copy"
}

chown_to_target() {
	local file
	local owner="$1"
	shift

	local user="${owner%:*}" group="${owner#*:}"
	# skip users not on target (e.g. old base OS)
	awk -v user="$user" -F: '$1 == user { exit(1); }' \
		< "$TARGET/etc/passwd" && return
	if [ "$user" != "$owner" ] && [ -n "$group" ]; then
		# same for group
		awk -v group="$group" -F: '$1 == group { exit(1); }' \
			< "$TARGET/etc/group" && return
	fi

	for file; do
		[ -L "$file" ] || [ -e "$file" ] || continue

		chroot "$TARGET" chown -hR "$owner" "/${file#"$TARGET"}" \
			|| error "Could not chown post files"
	done
}

post_chown_preserve_files() {
	local owner f
	[ -n "$(mkswu_var NO_PRESERVE_FILES)" ] && return
	local IFS=' '

	sed -ne 's:^CHOWN ::p' "$TARGET/etc/swupdate_preserve_files" \
		| sort -u > "$MKSWU_TMP/preserve_files_chown"
	while read -r owner f; do
		# we reset IFS everytime because we want IFS to be space for
		# read to split the first word (owner); but we need it to be
		# new line to not split paths with spaces (yet expand globs)
		IFS='
'
		# No quote to expand globs
		chown_to_target "$owner" $TARGET/$f
		IFS=' '
	done < "$MKSWU_TMP/preserve_files_chown"

	rm -f "$MKSWU_TMP/preserve_files_chown"
}

check_update_log_encryption() {
	# encrypt /var if we were requested to
	# note we do not "decrypt" a fs if the var is not set
	[ -z "$(mkswu_var ENCRYPT_USERFS)" ] && return

	local dev="$(findmnt -nr -o SOURCE /var/log)"
	[ -z "$dev" ] && return

	# already encrypted ?
	[ "$(lsblk -n -o type "$dev")" = "crypt" ] && return

	if mountpoint -q /var/log; then
		# umount if used
		rc-service syslog stop
		fuser -k /var/log
		# wait a bit as kill is async
		sleep 1
		umount /var/log \
			|| error "encryption was requested for /var/log but could not umount: aborting. Manually dismount it first"
	fi

	warning "Reformatting /var/log with encryption, current logs will be lost"

	luks_format "${partdev##*/}3"
	mkfs.ext4 -L logs "$dev" \
		|| error "Could not format ext4 onto $dev after encryption setup"
	mount -t ext4 "$dev" /var/log \
		|| error "Could not re-mount encrypted /var/log"

	if ! sed -i -e "s:[^ \t]*\(\t/var/log\t\):$dev\1:" /etc/fstab \
	    || ! persist_file /etc/fstab; then
		warning "Could not update the current rootfs fstab for encrypted /var/log," \
			"will not be able to mount /var/log in case of rollback"
	fi
	sed -i -e "s:[^ \t]*\(\t/var/log\t\):$dev\1:" /target/etc/fstab \
		|| error "Could not update fstab for encrypted /var/log"
}

post_rootfs() {
	# allow overriding for tests
	local TARGET="${TARGET:-/target}"
	# support older version of overlayfs
	local fsroot=/live/rootfs/
	[ -e "$fsroot" ] || fsroot=/

	# Sanity check: refuse to continue if someone tries to write a
	# rootfs that was corrupted or "too wrong": check for /bin/sh
	if ! [ -e /target/bin/sh ]; then
		error "No /bin/sh on target: something likely is wrong with rootfs, refusing to continue"
	fi
	local libc_arch
	case "$(uname -m)" in
	aarch64) libc_arch=aarch64;;
	armv7*) libc_arch=armv7;;
	esac
	if [ -z "$(mkswu_var NO_ARCH_CHECK)" ] && [ -n "$libc_arch" ] \
	    && ! ldd /target/bin/sh | grep -q "$libc_arch"; then
		error "/bin/sh was not dynamically linked or linked for a different arch than expected, refusing to continue." \
			"In case of false positive set MKSWU_NO_ARCH_CHECK=1"
	fi

	# if other fs was recreated: fix partition-specific things
	if [ -e /target/.created ]; then
		# fwenv: either generate a new one for mmc, or copy for sd boot (supersedes version in update)
		if [ -e "${rootdev}boot0" ]; then
			sed -e "s@${rootdev}boot[01]@${rootdev}boot${ab}@" \
					/etc/fw_env.config > /target/etc/fw_env.config \
				|| error "Could not write fw_env.config"
		elif [ -e /etc/fw_env.config ]; then
			cp /etc/fw_env.config /target/etc/fw_env.config \
				|| error "Could not copy fw_env.config"
		elif [ -e /target/boot/extlinux.conf ]; then
			sed -i -e "s/root=[^ ]*/root=LABEL=rootfs_${ab}/" /target/boot/extlinux.conf \
				|| error "Could not update extlinux.conf"
		fi

		# adjust fstab/partitions
		sed -i -e "s/boot_[01]/boot_${ab}/" /target/etc/fstab \
			|| error "Could not update fstab"
		local fstype mntopts="ro,noatime"
		fstype="$(findmnt -nr -o FSTYPE /target)" \
			|| error "Could not query rootfs' fstype"
		case "$fstype" in
		btrfs) mntopts="$mntopts,compress-force=zstd,discard=async";;
		ext4) ;;
		*) error "Unexpected fstype for rootfs $fstype";;
		esac
		if ! grep -qE "/dev/root\s+/\s+$fstype\s+$mntopts\s" /target/etc/fstab; then
			sed -i -e "s@^/dev/root.*@/dev/root\t/\t\t\t\t$fstype\t$mntopts\t0 0@" \
					/target/etc/fstab \
				|| error "Could not update fstab"
		fi
		check_update_log_encryption

		# use appfs storage for podman if used previously
		if grep -q 'graphroot = "/var/lib/containers/storage' /etc/containers/storage.conf 2>/dev/null; then
			# newer versions also remove the ro store, but only do it if done previously
			local remove_ro_store=""
			grep -q "containers/storage_readonly" /etc/containers/storage.conf \
				|| remove_ro_store='/containers\/storage_readonly/d'

			sed -i -e 's@graphroot = .*@graphroot = "/var/lib/containers/storage"@' \
				-e "$remove_ro_store" /target/etc/containers/storage.conf \
				|| error "could not rewrite storage.conf"
		fi
		if update_baseos; then
			. "$SCRIPTSDIR/post_rootfs_baseos.sh"
		fi
	fi

	# extra fixups on update
	if update_baseos; then
		# keep passwords around
		update_shadow || error "Could not update user list"

		# update preserve_files owners when required
		# (after update_shadow)
		post_chown_preserve_files
	fi

	# remove open access swupdate certificate or complain
	# This has to be done even if rootfs isn't modified because we
	# need to remove one-time cert added through 'abos-ctrl certificates'
	update_swupdate_certificate

	# in theory we should also check shadow if no update, but shadow can
	# only be updated if rootfs changed so we trust the old system
	# (this might miss a password removal if done through persist_file)
	if update_rootfs; then
		check_shadow_empty_password
	else
		# if certificates changed we ended up updating os,
		# update timestamp
		if ! cmp -s /etc/swupdate.pem /target/etc/swupdate.pem; then
			update_rootfs_timestamp
		fi

	fi

	# mark filesystem as ready for reuse if something failed
	rm -f /target/.created \
		|| error "Could not remove .created internal file from rootfs"

	# and finally set version where appropriate.
	if ! needs_reboot; then
		# record current versions to other rootfs
		cp /etc/sw-versions /target/etc/sw-versions \
			|| error "Could not copy current sw-versions to other fs"
		# updating current version with what is being installed:
		# we should avoid failing from here on.
		update_running_versions "$MKSWU_TMP/sw-versions.merged"
		soft_fail=1
	else
		cp "$MKSWU_TMP/sw-versions.merged" "/target/etc/sw-versions" \
			|| error "Could not set sw-versions"
	fi

	# free unused blocks at mmc level
	fstrim /target

	rm -f "$MKSWU_TMP/sw-versions.present"
}

[ -n "$TEST_SCRIPTS" ] && return

post_rootfs
