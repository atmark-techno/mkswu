link_exists() {
	local base="$1"
	local target="$2"

	if [ "${target:0:1}" = "/" ]; then
		[ -e "/target/$target" ]
	else
		[ -e "/target/$base/$target" ]
	fi
}

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
	grep -q "ALLOW_EMPTY_LOGIN" "$SWDESC" && return
	user=$(awk -F: '$2 == "" { print $1 } ' "$NSHADOW")
	[ -z "$user" ] || error "the following users have an empty password, failing update: $user"

}


SWUPDATE_PEM=/target/etc/swupdate.pem

update_swupdate_certificate()  {
	local certsdir cert pubkey external="" update=""

	# split swupdate.pem into something we can handle, then match
	# with known keys and update as appropriate

	certsdir=$(mktemp -d "$SCRIPTSDIR/certs.XXXXXX") \
		|| error "Could not create temp dir"
	awk '/BEGIN CERTIFICATE/ { idx++; outfile="'"$certsdir"'/cert." idx }
	     outfile { print > outfile }
	     /END CERTIFICATE/ { outfile="" }' "$SWUPDATE_PEM"
	for cert in "$certsdir"/*; do
		pubkey=$(openssl x509 -noout -in "$cert" -pubkey | sed -e '/-----/d' | tr -d '\n')
		case "$pubkey" in
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEYTN7NghmISesYQ1dnby5YkocLAe2/EJ8OTXkx/xGhBVlJ57eGOovtPORd/JMkA6lWI0N/pD5p6eUGcwrQvRtsw==")
			# Armadillo public one-time key, remove it.
			rm -f "$cert"
			update=1
			;;
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEjgbd3SI8+iof3TLL9qTGNlQN84VqkESPZ3TSUkYUgTiEL3Bi1QoYzGWGqfdmrLiNsgJX4QA3gpaC19Q+fWOkEA==")
			# Armadillo internal key, leave it if present.
			;;
		*)
			# Any other key
			external=1
			;;
		esac
	done

	if [ -n "$update" ]; then
		# fail if no user key has been provided
		if [ -z "$external" ]; then
			# just skip this step if flag is set
			grep -q "ALLOW_PUBLIC_CERT" "$SWDESC" \
				|| error "The public one-time swupdate certificate can only be used once. Please add your own certificate. Failing update."
		else
			cat "$certsdir"/* > "$SWUPDATE_PEM" \
				|| error "Could not recreate swupdate.pem certificate"
		fi
	fi

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
		# source file must exist
		[ -e "$file" ] || continue
		dir="${file%/*}"
		mkdir_p_target "$dir"
		rm -rf "$TARGET/$f"
		cp -a "$file" "$TARGET/$file"
	done
}

post_copy_preserve_files() {
	local f
	local TARGET="${TARGET:-/target}"
	local IFS='
'
	grep -q "NO_PRESERVE_FILES" "$SWDESC" && return

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

	# add /var/at-log to fstab
	if version_greater_than "$baseos_version" "3.15.0-at.1" \
	    && grep -q /dev/mmcblk2 /proc/cmdline \
	    && [ -e /dev/mmcblk2gp1 ] \
	    && ! grep -q /dev/mmcblk2gp1 /target/etc/fstab; then
		cat >> /target/etc/fstab <<'EOF' \
			|| error "Could not append to target /etc/fstab"
/dev/mmcblk2gp1	/var/at-log			vfat	defaults			0 0
EOF
	fi

	# add noatime to fstab
	if version_greater_than "$baseos_version" "3.15.0-at.2" \
	    && ! grep -q noatime /target/etc/fstab; then
		sed -i -e '/squashfs/ ! s/defaults/&,noatime/' \
				-e 's/,subvol=/,noatime&/' /target/etc/fstab \
			|| error "Could not update fstab"
	fi
}


post_rootfs() {
	# Sanity check: refuse to continue if someone tries to write a
	# rootfs that was corrupted or "too wrong": check for /bin/sh
	if ! [ -e /target/bin/sh ]; then
		error "No /bin/sh on target: something likely is wrong with rootfs, refusing to continue"
	fi

	# if other fs was recreated: fix partition-specific things
	if [ -e /target/.created ]; then
		rm -f /target/.created

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

	# and finally set version where appropriate.
	if ! needs_reboot; then
		# updating current version with what is being installed:
		# we should avoid failing from here on.
		update_running_versions "$SCRIPTSDIR/sw-versions.merged"
		soft_fail=1
	else
		cp "$SCRIPTSDIR/sw-versions.merged" "/target/etc/sw-versions" \
			|| error "Could not set sw-versions"
	fi


	rm -f "$SCRIPTSDIR/sw-versions.merged" "$SCRIPTSDIR/sw-versions.present"
}

[ -n "$TEST_SCRIPTS" ] && return

post_rootfs
