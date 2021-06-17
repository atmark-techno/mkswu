post_rootfs() {
	# if other fs wasn't up to date: fix partition-specific things
	if ! grep -q "other_rootfs_uptodate" "/etc/sw-versions" 2>/dev/null; then
		if [ "$mmcblk" = "/dev/mmcblk2" ]; then
			cat > /target/etc/fw_env.config <<EOF
${mmcblk}boot${ab} 0x3fe000 0x2000
${mmcblk}boot${ab} 0x3fa000 0x2000
EOF
		fi

		# adjust ab_boot
		sed -i -e "s/boot_[01]/boot_${ab}/" /target/etc/fstab
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
