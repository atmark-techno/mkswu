update_shadow_user() {
	local user="$1"
	local oldpass

	oldpass=$(awk -F':' '$1 == "'"$user"'" && $3 != "0"' "$SHADOW" \
			| sed -e 's/:/\\:/g')
	# password was never set: skip
	[ -n "$oldpass" ] || return
	# password already set on target: also skip
	grep -qE "^$user:[^:]" "$NSHADOW" && return

	if grep -qE "^$user:" "$NSHADOW"; then
		sed -i -e 's:^'"$user"'\:.*:'"$oldpass"':' "$NSHADOW"
	else
		printf "%s\n" "$oldpass" >> "$NSHADOW"
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
	local PASSWD="${PASSWD:-/etc/passwd}"
	local NPASSWD="${NPASSWD:-/target/etc/passwd}"
	local SHADOW="${SHADOW:-/etc/shadow}"
	local NSHADOW="${NSHADOW:-/target/etc/shadow}"
	local GROUP="${GROUP:-/etc/group}"
	local NGROUP="${NGROUP:-/target/etc/group}"

	# "$PASSWD", group and shadow have to be part of rootfs as
	# rootfs updates can change system users, but we want to keep
	# "real" users as well so copy them over manually:
	# - copy non-existing "real" groups (gid >= 1000)
	# - for each real user (root or uid >= 1000), copy its password
	# if the old one not set and add it to groups it had been added to
	awk -F: '$3 >= 1000 && $3 < 65500 { print $1 }' < "$GROUP" |
		while read -r group; do
			grep -qE "^$group:" "$NGROUP" \
				|| grep -E "^$group:" "$GROUP" >> "$NGROUP"
		done

	awk -F: '$3 == 0 || ( $3 >= 1000 && $3 < 65500 ) { print $1 }' < "$PASSWD" |
		while read -r user; do
			grep -qE "^$user:" "$NPASSWD" \
				|| grep -E "^$user:" "$PASSWD" >> "$NPASSWD"
			update_shadow_user "$user"
			update_user_groups "$user"
		done

	# check there are no user with empty login
	# unless the update explicitely allows it
	[ -n "$(mkswu_var ALLOW_EMPTY_LOGIN)" ] && return
	user=$(awk -F: '$2 == "" { print $1 } ' "$NSHADOW")
	[ -z "$user" ] || error "the following users have an empty password, failing update: $user"

}


SWUPDATE_PEM=/target/etc/swupdate.pem

update_swupdate_certificate()  {
	local certsdir cert pubkey
	local public_onetime_path=""
	local atmark_present="" atmark_seen=""
	local user_present="" user_seen=""

	# what certificates were embedded into swu, if any?
	for cert in "$SCRIPTSDIR/certs_atmark/"*; do
		[ -e "$cert" ] && atmark_present=1
		break
	done
	for cert in "$SCRIPTSDIR/certs_user/"*; do
		[ -e "$cert" ] && user_present=1
		break
	done

	# split swupdate.pem into something we can handle, then match
	# with known certificates and update as appropriate

	certsdir=$(mktemp -d "$SCRIPTSDIR/certs.XXXXXX") \
		|| error "Could not create temp dir"
	awk '! outfile { idx++; outfile="'"$certsdir"'/cert." idx }
	     outfile { print > outfile }
	     /END CERTIFICATE/ { outfile="" }' "$SWUPDATE_PEM"
	for cert in "$certsdir"/*; do
		[ -e "$cert" ] || continue
		pubkey=$(openssl x509 -noout -in "$cert" -pubkey | sed -e '/-----/d' | tr -d '\n')
		case "$pubkey" in
		# Armadillo public one-time cert
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEYTN7NghmISesYQ1dnby5YkocLAe2/EJ8OTXkx/xGhBVlJ57eGOovtPORd/JMkA6lWI0N/pD5p6eUGcwrQvRtsw==")
			# remove duplicates if it was already set
			[ -n "$public_onetime_path" ] && rm -f "$public_onetime_path"
			# we don't remove it immediately because we allow updates from atmark
			# updates to leave it
			public_onetime_path="$cert"
			;;
		# certificate for atmark are handled separately
		# atmark-1|atmark-2
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEjgbd3SI8+iof3TLL9qTGNlQN84VqkESPZ3TSUkYUgTiEL3Bi1QoYzGWGqfdmrLiNsgJX4QA3gpaC19Q+fWOkEA=="| \
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAERkRP5eTXBTG760gEmBfCBz4fWyYfUx3a+sYyHe4uc1sQN2bavxfaBlJmyGI4MY/Pkjh5FDVcddZfil552WUoWQ==")
			# atmark certificates: delete if we have new ones, or just keep.
			[ -n "$atmark_present" ] && rm -f "$cert"
			atmark_seen=1
			;;
		*)
			# user certificates: delete if we have new ones,
			# otherwise keep whatever we have here.
			[ -n "$user_present" ] && rm -f "$cert"
			user_seen=1
			;;
		esac
	done

	if [ -n "$public_onetime_path" ]; then
		if [ -z "$user_seen$user_present" ]; then
			# don't remove one-time cert if no external cert provided
			# fail unless explicitely allowed
			[ -n "$(mkswu_var ALLOW_PUBLIC_CERT)" ] \
				|| error "The public one-time swupdate certificate can only be used once. Please add your own certificate. Failing update."
		else
			rm -f "$public_onetime_path"
		fi
	fi
	(
		# ignore errors, might not be any cert left here
		cat "$certsdir"/* 2>/dev/null
		if [ -n "$atmark_seen" ]; then
			# only add atmark certs if they're currently installed
			for cert in "$SCRIPTSDIR/certs_atmark/"*; do
				[ -e "$cert" ] || continue
				echo "# ${cert##*/}"
				cat "$cert" || exit 1
			done
		fi
		for cert in "$SCRIPTSDIR/certs_user/"*; do
			[ -e "$cert" ] || continue
			echo "# ${cert##*/}"
			cat "$cert" || exit 1
		done
	) > "$SWUPDATE_PEM" \
		|| error "Could not recreate swupdate.pem certificates"

	rm -rf "$certsdir"
}

update_running_versions() {
	cp "$1" /etc/sw-versions || error "Could not update /etc/sw-versions"

	[ "$(stat -f -c %T /etc/sw-versions)" = "overlayfs" ] || return

	# support older version of overlayfs
	local fsroot=/live/rootfs
	[ -e "$fsroot" ] || fsroot=/

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
		cp -a "$file" "$TARGET/$file" \
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
		| sort -u > "$TMPDIR/preserve_files_post"
	while read -r f; do
		# No quote to expand globs
		overwrite_to_target $f
	done < "$TMPDIR/preserve_files_post"

	rm -f "$TMPDIR/preserve_files_post"
}


# strict version comparison
# when we have a bug for e.g. until 3.15.0-at.1,
# we must also include 3.15.0-at.1.<date> for people who built
# manual updates, so we must check < 3.15.0-at.2 in practice.
version_greater_than() {
	! printf "%s\n" "$2" "$1" | sort -VC
}

baseos_upgrade_fixes() {
	local baseos_version

	# if user has local certificates we should regenerate the bundle
	if stat /target/usr/local/share/ca-certificates/* >/dev/null 2>&1; then
		FILTER="WARNING: ca-certificates.crt does not contain exactly one certificate or CRL: skipping" \
			podman run --net=none --rootfs /target update-ca-certificates 2>/dev/null \
				|| error "update-ca-certificates failed"
	fi

	### workaround section, these can be removed once we consider we no longer
	### support a given version.

	# note this is the currently running version,
	# not the version we install (which would always be too recent!)
	baseos_version=$(cat /etc/atmark-release) || return

	# not a baseos install? skip fixes...
	[ -n "$baseos_version" ] || return

	# add /var/at-log to fstab (added in 3.15.0-at.1)
	if grep -q /dev/mmcblk2 /proc/cmdline \
	    && [ -e /dev/mmcblk2gp1 ] \
	    && ! grep -q /dev/mmcblk2gp1 /target/etc/fstab; then
		cat >> /target/etc/fstab <<'EOF' \
			|| error "Could not append to target /etc/fstab"
/dev/mmcblk2gp1	/var/at-log			vfat	defaults			0 0
EOF
	fi

	# add noatime to fstab (added in 3.15.0-at.2)
	if ! grep -q noatime /target/etc/fstab; then
		sed -i -e '/squashfs/ ! s/defaults/&,noatime/' \
				-e 's/,subvol=/,noatime&/' /target/etc/fstab \
			|| error "Could not update fstab"
	fi

	# Remove /var/log/rc.log we no longer write to
	# (removed in 3.15.4-at.6)
	if [ -e /var/log/rc.log ]; then
		rm -f /var/log/rc.log
	fi

	# Lock atmark account if it has no password
	# (locked by default in 3.16-at.1)
	if grep -q 'atmark::' /target/etc/shadow; then
		sed -i -e 's/atmark::/atmark:!:/' /target/etc/shadow \
			|| error "Could not lock atmark user"
	fi

	# Increase swupdate.cfg verbosity
	# (done in 3.16-at.1)
	if grep -q 'loglevel = 2;' /target/etc/swupdate.cfg; then
		sed -i -e 's/loglevel = 2/loglevel = 3/' /target/etc/swupdate.cfg \
			|| error "Could not update swupdate.cfg"
	fi

}

check_update_log_encryption() {
	# encrypt /var if we were requested to
	# note we do not "decrypt" a fs if the var is not set
	[ -z "$(mkswu_var ENCRYPT_USERFS)" ] && return

	local dev="$(findmnt -n -o SOURCE /var/log)"
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
	mount "$dev" /var/log \
		|| error "Could not re-mount encrypted /var/log"

	sed -i -e "s:[^ \t]*\(\t/var/log\t\):$dev\1:" /target/etc/fstab \
		|| error "Could not update fstab for encrypted /var/log"
}

post_rootfs() {
	# Sanity check: refuse to continue if someone tries to write a
	# rootfs that was corrupted or "too wrong": check for /bin/sh
	if ! [ -e /target/bin/sh ]; then
		error "No /bin/sh on target: something likely is wrong with rootfs, refusing to continue"
	fi

	# if other fs was recreated: fix partition-specific things
	if [ -e /target/.created ]; then
		# fwenv: either generate a new one for mmc, or copy for sd boot (supersedes version in update)
		if [ "$rootdev" = "/dev/mmcblk2" ]; then
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
			sed -i -e 's@graphroot = .*@graphroot = "/var/lib/containers/storage"@' \
				/target/etc/containers/storage.conf \
				|| error "could not rewrite storage.conf"
		fi
		if update_baseos; then
			baseos_upgrade_fixes
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
