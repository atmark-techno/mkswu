update_running_versions() {
	cp "$1" /etc/sw-versions || error "Could not update /etc/sw-versions"

	[ "$(stat -f -c %T /etc/sw-versions)" = "overlayfs" ] || return

	# bind-mount / somewhere else to write below it as well
	mount --bind "$fsroot" /target || error "Could not bind mount rootfs"
	mount -o remount,rw /target || error "Could not make rootfs rw"
	cp /etc/sw-versions /target/etc/sw-versions \
		|| error "Could not write $1 to /etc/sw-versions"
	umount /target || error "Could not umount rootfs rw copy"
}

overwrite_to_target() {
	local file
	local dir

	for file; do
		# source file must exist... being careful of symlinks
		[ -L "$file" ] || [ -e "$file" ] || continue

		dir="${file%/*}"
		mkdir_p_target "$dir"
		rm -rf --one-file-system "${TARGET:-inval}/$f"
		cp -a "$fsroot$file" "$TARGET/$file" \
			|| error "Failed to copy $file from previous rootfs"
	done
}

post_copy_preserve_files() {
	local f
	local TARGET="${TARGET:-/target}"
	local IFS='
'
	[ -n "$(mkswu_var NO_PRESERVE_FILES)" ] && return

	sed -ne 's:^POST /:/:p' "$TARGET/etc/swupdate_preserve_files" \
		| sort -u > "$SCRIPTSDIR/preserve_files_post"
	while read -r f; do
		# No quote to expand globs
		overwrite_to_target $f
	done < "$SCRIPTSDIR/preserve_files_post"

	rm -f "$SCRIPTSDIR/preserve_files_post"
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

	warning "Reformatting /var/log with encryption, current logs will be lost" \
		"Also, in case of update failure or rollback current system will not be able to mount it"

	luks_format "${partdev##*/}3"
	mkfs.ext4 -L logs "$dev" \
		|| error "Could not format ext4 onto $dev after encryption setup"
	mount -t ext4 "$dev" /var/log \
		|| error "Could not re-mount encrypted /var/log"

	sed -i -e "s:[^ \t]*\(\t/var/log\t\):$dev\1:" /target/etc/fstab \
		|| error "Could not update fstab for encrypted /var/log"
}

post_rootfs() {
	# support older version of overlayfs
	local fsroot=/live/rootfs/ libc_arch=""
	[ -e "$fsroot" ] || fsroot=/

	# Sanity check: refuse to continue if someone tries to write a
	# rootfs that was corrupted or "too wrong": check for /bin/sh
	if ! [ -e /target/bin/sh ]; then
		error "No /bin/sh on target: something likely is wrong with rootfs, refusing to continue"
	fi
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
			cat > /target/etc/fw_env.config <<EOF \
				|| error "Could not write fw_env.config"
${rootdev}boot${ab} 0x3fe000 0x2000
${rootdev}boot${ab} 0x3fa000 0x2000
EOF
		else
			cp /etc/fw_env.config /target/etc/fw_env.config \
				|| error "Could not copy fw_env.config"
		fi

		# adjust ab_boot
		sed -i -e "s/boot_[01]/boot_${ab}/" /target/etc/fstab \
			|| error "Could not update fstab"
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
			if [ -e "$SCRIPTSDIR/post_rootfs_baseos.sh" ]; then
				. "$SCRIPTSDIR/post_rootfs_baseos.sh"
			fi
			post_copy_preserve_files
		fi
	fi

	# extra fixups on update
	# in theory we should also check shadow/cert if no update, but the system
	# needs extra os update to start containers so this is enough for safety check
	if update_rootfs; then
		# keep passwords around, and make sure there are no open access user left
		update_shadow

		# remove open access swupdate certificate or complain
		update_swupdate_certificate
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
		update_running_versions "$SCRIPTSDIR/sw-versions.merged"
		soft_fail=1
	else
		cp "$SCRIPTSDIR/sw-versions.merged" "/target/etc/sw-versions" \
			|| error "Could not set sw-versions"
	fi

	# free unused blocks at mmc level
	fstrim /target

	rm -f "$SCRIPTSDIR/sw-versions.present"
}

[ -n "$TEST_SCRIPTS" ] && return

post_rootfs
