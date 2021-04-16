post_rootfs() {
	# three patterns:
	# - we wrote some data and need rebooting:
	#   * rootfs flag was cleared by pre script if set
	# - we didn't write anything, but don't have other_rootfs_uptodate flag
	#   * set flag in both version files
	# - we didn't write anything and flag is already set
	#   * nothing to do
	if ! needs_reboot; then
		# if we're not rebooting, the other rootfs is now up to date
		grep -q "other_rootfs_uptodate" "/etc/sw-versions" && return
		echo "other_rootfs_uptodate 1" >> /target/etc/sw-versions
		update_running_versions sed -e '$aother_rootfs_uptodate 1'
	fi

	grep -v "other_rootfs_uptodate" "$SCRIPTSDIR/sw-versions.merged" > \
		"/target/etc/sw-versions"

	rm -f "$SCRIPTSDIR/sw-versions.merged" "$SCRIPTSDIR/sw-versions.present"

	if [ "$mmcblk" = "/dev/mmcblk2" ]; then
		cat > /target/etc/fw_env.config <<EOF
${mmcblk}boot${ab} 0x3fe000 0x2000
${mmcblk}boot${ab} 0x3fa000 0x2000
EOF
	fi

	sed -i -e "s/storage_[01]/storage_${ab}/" \
		-e "s/volumes_[01]/volumes_${ab}/" /target/etc/fstab
}

post_rootfs
