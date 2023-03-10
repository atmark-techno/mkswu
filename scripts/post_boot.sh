allow_upgrade_available() {
	# Do not set upgrade_available if other boot is encrypted,
	# we would not be able to boot into it.
	[ -z "$encrypted_boot" ] || return

	# Cannot fw_setenv without this...
	[ -s /etc/fw_env.config ] || return

	# Do not set upgrade_available if it is not set in default
	# configuration.
	cat /boot/uboot_env.d/* 2>/dev/null | awk -F= '
		$1 == "upgrade_available" {
			set=$2
		}
		END {
			if (set != "1")
				exit(1)
		}'
}

cleanup_target() {
	sync
	cleanup

	# Mark other fs as usable again unless encrypted boot is used
	if allow_upgrade_available; then
		fw_setenv_nowarn upgrade_available 1 \
			|| warn "could not restore rollback"
	fi
}

cleanup_boot() {
	local dev encrypted_boot=""

	if ! needs_reboot; then
		cleanup_target
		return
	fi

	if fw_printenv dek_spl_offset | grep -q dek_spl_offset=0x; then
		encrypted_boot=1
	fi

	# if uboot was installed, try to safeguard against u-boot
	# installed on incompatible arch.
	# This is not strictly enough but should prevent most complete
	# bricks from installing an incompatible SWU...
	if [ -e /dev/swupdate_bootdev ] \
	    && [ -z "$encrypted_boot" ] \
	    && [ -z "$(mkswu_var NO_ARCH_CHECK)" ]; then
		case "$(uname -m)" in
		aarch64)
			dd if=/dev/swupdate_bootdev  bs=1M count=4 \
					| grep -m 1 -q aarch64 \
				|| error "Installed u-boot does not appear to be for aarch64, aborting!" \
					"In case of false positive, set MKSWU_NO_ARCH_CHECK=1"
			;;
		armv7*)
			dd if=/dev/swupdate_bootdev  bs=1M count=4 \
					| grep -m 1 -q armv7 \
				|| error "Installed u-boot does not appear to be for armv7, aborting!" \
					"In case of false positive, set MKSWU_NO_ARCH_CHECK=1"
			;;
		esac
	fi

	# reset uboot env from config
	if stat /target/boot/uboot_env.d/* > /dev/null 2>&1; then
		# We need to reset env everytime to avoid leaving new variables unset
		# after no-boot upgrades.
		# note this will not clear extra values that had been set manually
		# but are not present in configs, we should zero the env block for
		# that... Maybe if that becomes a problem.
		cat /target/boot/uboot_env.d/* > "$SCRIPTSDIR/uboot_env" \
			|| error "uboot env files existed but could not merge them"
		grep -qE "^bootcmd=" "$SCRIPTSDIR/uboot_env" \
			|| error "uboot env files existed, but bootcmd is not set. Refusing to continue." \
				"Please update your Base OS image or provide default environment first."
		fw_setenv_nowarn --config "/target/etc/fw_env.config" \
				--script "$SCRIPTSDIR/uboot_env" \
				--defenv /dev/null \
			|| error "Could not set uboot env"
		rm -f "$SCRIPTSDIR/uboot_env"
	fi

	if [ -e "${rootdev}boot0" ]; then
		cleanup_target
		if [ -n "$encrypted_boot" ]; then
			echo "writing encrypted uboot update, rollback will be done by current uboot on reboot"
			# make sure we're still set to boot on current uboot
			mmc bootpart enable "$((!ab+1))" 0 "$rootdev"
			fw_setenv_nowarn encrypted_update_available 1
		else
			echo "setting mmc bootpart enable $((ab+1))"
			mmc bootpart enable "$((ab+1))" 0 "$rootdev" \
				|| error "Could not flip mmc boot flag"
		fi
	elif [ -s /etc/fw_env.config ]; then
		cleanup_target
		# if uboot env is supported, use it (e.g. sd card)
		fw_setenv_nowarn mmcpart $((ab+1)) \
			|| error " Could not setenv mmcpart"
	elif [ -e /target/boot/extlinux.conf ]; then
		# assume gpt boot e.g. extlinux
		sgdisk --attributes=$((ab+1)):set:2 --attributes=$((!ab+1)):clear:2 "$rootdev" \
			|| error "Could not set boot attribute"

		sed -i -e "s/root=[^ ]*/root=LABEL=rootfs_${ab}/" /target/boot/extlinux.conf \
			|| error "Could not update extlinux.conf"
		extlinux -i /target/boot || error "Could not reinstall bootloader"
		cleanup_target
	else
		error "Do not know how to A/B switch this system"
	fi

	# from here on, failure is not appropriate.
	soft_fail=1
}

cleanup_boot
