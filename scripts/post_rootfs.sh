link_exists() {
	local base="$1"
	local target="$2"

	if [ "${target:0:1}" = "/" ]; then
		[ -e "/target/$target" ]
	else
		[ -e "/target/$base/$target" ]
	fi
}

update_shadow() {
	local user="$1"
	local oldpass newpass_lastday

	oldpass=$(awk -F':' '$1 == "'"$user"'" && $3 != "0"' /etc/shadow)
	# password was never set: skip
	[ -n "$oldpass" ] || return

	newpass_lastday=$(awk -F':' '$1 == "'"$user"'" { print($3 == "" ? 1 : $3) }' /target/etc/shadow)
	# user doesn't exist on dest: skip
	[ -n "$newpass_lastday" ] || return
	# password already set on dest: skip
	[ "$newpass_lastday" != 0 ] && return

	sed -i -e 's:^'"$user"'\:.*:'"${oldpass//:/\\:}"':' /target/etc/shadow
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

		if [ -e /target/boot/extlinux.conf ]; then
			sed -i -e "s/root=[^ ]*/root=LABEL=rootfs_${ab}/" /target/boot/extlinux.conf
			extlinux -i /target/boot
		fi

		# keep same storage.conf as current if using link
		if storage_conf_link=$(readlink /etc/containers/storage.conf) \
		    && [ "$storage_conf_link" != "$(readlink /target/etc/containers/storage.conf)" ] \
		    && link_exists "/etc/containers" "$storage_conf_link"; then
			rm -f /target/etc/containers/storage.conf
			ln -s "$storage_conf_link" /target/etc/containers/storage.conf
		fi

		update_shadow root
		update_shadow atmark
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
