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

	oldpass=$(awk -F':' '$1 == "'"$user"'" && $3 != "0"' /etc/shadow)
	# password was never set: skip
	[ -n "$oldpass" ] || return

	if grep -qE "^$user:" /target/etc/shadow; then
		sed -i -e 's:^'"$user"'\:.*:'"${oldpass//:/\\:}"':' /target/etc/shadow
	else
		echo "$oldpass" >> /target/etc/shadow
	fi || error "Could not update shadow for $user"
}

update_user_groups() {
	local user="$1"
	local group

	awk -F: '$4 ~ /(,|^)'"$user"'(,|$)/ { print $1 }' < /etc/group |
		while read -r group; do
			# already set
			grep -qE "^$group:.*[:,]$user(,|$)" /target/etc/group \
				&& continue

			if grep -qE "^$group:.*:$" /target/etc/group; then
				sed -i -e 's/^'"$group"':.*:/&'"$user"'/' /target/etc/group
			else
				sed -i -e 's/^'"$group"':.*/&,'"$user"'/' /target/etc/group
			fi || error "Could not update group $group / $user"
		done
}

update_shadow() {
	local user group

	# /etc/passwd, group and shadow have to be part of rootfs as
	# rootfs updates can change system users, but we want to keep
	# "real" users as well so copy them over manually:
	# - copy non-existing "real" groups (gid >= 1000)
	# - for each real user (root or uid >= 1000), copy its password
	# if the old one not set and add it to groups it had been added to
	awk -F: '$3 >= 1000 && $3 < 65500 { print $1 }' < /etc/group |
		while read -r group; do
			grep -qE "^$group:" /target/etc/group \
				|| grep -E "^$group:" /etc/group >> /target/etc/group
		done

	awk -F: '$3 == 0 || ( $3 >= 1000 && $3 < 65500 ) { print $1 }' < /etc/passwd |
		while read -r user; do
			update_shadow_user "$user"
			update_user_groups "$user"
		done
}

post_rootfs() {
	local storage_conf_link
	# Sanity check: refuse to continue if someone tries to write a
	# rootfs that was corrupted or "too wrong": check for /bin/sh
	if ! [ -e /target/bin/sh ]; then
		error "No /bin/sh on target: something likely is wrong with rootfs, refusing to continue"
	fi

	# if other fs wasn't up to date: fix partition-specific things
	# note that this means these files cannot be updated through swupdate
	# as this script will always reset them.
	if ! grep -q "other_rootfs_uptodate" "/etc/sw-versions" 2>/dev/null; then
		# fwenv: either generate a new one for mmc, or copy for sd boot (only one env there)
		if [ "$rootdev" = "/dev/mmcblk2" ]; then
			cat > /target/etc/fw_env.config <<EOF
${rootdev}boot${ab} 0x3fe000 0x2000
${rootdev}boot${ab} 0x3fa000 0x2000
EOF
		else
			cp /etc/fw_env.config /target/etc/fw_env.config
		fi

		# adjust ab_boot
		sed -i -e "s/boot_[01]/boot_${ab}/" /target/etc/fstab

		# keep same storage.conf as current if using link
		if storage_conf_link=$(readlink /etc/containers/storage.conf) \
		    && [ "$storage_conf_link" != "$(readlink /target/etc/containers/storage.conf)" ] \
		    && link_exists "/etc/containers" "$storage_conf_link"; then
			rm -f /target/etc/containers/storage.conf
			ln -s "$storage_conf_link" /target/etc/containers/storage.conf
		fi

		update_shadow
	fi

	# Three patterns:
	# - we didn't update rootfs, but other rootfs wasn't up to date yet
	#   * set flag in both version files
	# - we didn't update rootfs, other rootfs already up to date
	#   * other rootfs untouched, update version files to current partition
	# - we wrote some data and need rebooting:
	#   * rootfs uptodate flag was cleared by pre script
	#   * update version files to target partition
	if ! needs_reboot; then
		# if we're not rebooting, only update current versions and mark
		# the other rootfs up to date
		if ! grep -q "other_rootfs_uptodate" "/etc/sw-versions"; then
			echo "other_rootfs_uptodate 1" >> /target/etc/sw-versions
			echo "other_rootfs_uptodate 1" >> "$SCRIPTSDIR/sw-versions.merged"
		fi
		
		update_running_versions "$SCRIPTSDIR/sw-versions.merged"
	else
		grep -v "other_rootfs_uptodate" "$SCRIPTSDIR/sw-versions.merged" > \
			"/target/etc/sw-versions"
	fi


	rm -f "$SCRIPTSDIR/sw-versions.merged" "$SCRIPTSDIR/sw-versions.present"
}

post_rootfs
