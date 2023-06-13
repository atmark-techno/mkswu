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

reset_uboot_env() {
	local env_dev env_offset env_sz

	# not applicable to this target
	[ -e /target/etc/fw_env.config ] || return

	# Get environment device, offset and size
	# This assumes a single device contains env with nothing in
	# between redundant envs
	env_dev=$(awk '/^[^#]/ && $2 > 0 {
			if (!start || $2 < start)
				start = $2;
			if (!end || $2 + $3 > end)
				end = $2 + $3;
			if (dev && dev != $1) {
				print "Multiple devices in fw_env.config is not supported" > "/dev/stderr"
				exit(1)
			}
			dev=$1
		}
		END {
			if (!start) exit(1);
			printf("%s,%d,%d\n", dev, start, end-start);
		}
		' < /target/etc/fw_env.config) \
		|| error "Could not get boot env location"
	# ugly sh-compatible way of splitting vars...
	env_sz="${env_dev##*,}"
	env_dev="${env_dev%,*}"
	env_offset="${env_dev##*,}"
	env_dev="${env_dev%,*}"
	env_dev="${env_dev#/dev/}"

	local force_ro=""
	# SD cards have force_ro, but default to 0 and
	# fw_setenv do not handle it: only make sure to unlock
	# (and relock!) if previously locked.
	if [ "$(cat "/sys/block/$env_dev/force_ro" 2>/dev/null)" = 1 ]; then
		force_ro=1
	fi
	if [ -n "$force_ro" ]; then
		echo 0 > "/sys/block/$env_dev/force_ro" \
			|| error "Could not make $env_dev read-write"
	fi

	local rc
	dd if=/dev/zero of="/dev/$env_dev" bs="$env_sz" count=1 \
		seek="$env_offset" oflag=seek_bytes \
		conv=fdatasync status=none
	rc=$?
	if [ -n "$force_ro" ]; then
		echo 1 > "/sys/block/$env_dev/force_ro" \
			|| error "Could not make $env_dev read-only again"
	fi
	[ "$rc" = 0 ] || error "Could not clear uboot env"

	# stop here if nothing in uboot_env.d
	grep -qE '^[^#]' /target/boot/uboot_env.d/* 2>/dev/null || return
	grep -qE "^bootcmd=" /target/boot/uboot_env.d/* \
		|| error "uboot env files existed, but bootcmd is not set. Refusing to continue." \
			"Please update your Base OS image or provide default environment first."

	cat /target/boot/uboot_env.d/* \
		| fw_setenv_nowarn --config "/target/etc/fw_env.config" \
			--script - \
			--defenv /dev/null \
		|| error "Could not set uboot env"
	rm -f "$SCRIPTSDIR/uboot_env"
}

cleanup_boot() {
	local encrypted_boot=""

	if ! needs_reboot; then
		cleanup_target
		return
	fi

	if [ -e /etc/fw_env.config ] \
	    && fw_printenv dek_spl_offset | grep -q dek_spl_offset=0x; then
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
			dd if=/dev/swupdate_bootdev bs=1M count=4 status=none \
					| grep -m 1 -q aarch64 \
				|| error "Installed u-boot does not appear to be for aarch64, aborting!" \
					"In case of false positive, set MKSWU_NO_ARCH_CHECK=1"
			;;
		armv7*)
			dd if=/dev/swupdate_bootdev bs=1M count=4 status=none \
					| grep -m 1 -q armv7 \
				|| error "Installed u-boot does not appear to be for armv7, aborting!" \
					"In case of false positive, set MKSWU_NO_ARCH_CHECK=1"
			;;
		esac
	fi

	# reset uboot env from config everytime:
	#  - we need to clear env after boot updates
	#  - we want uboot_env.d updates immediately, always
	reset_uboot_env

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
		extlinux -i /target/boot 2>&1 || error "Could not reinstall bootloader"
		cleanup_target
	else
		error "Do not know how to A/B switch this system"
	fi

	# from here on, failure is not appropriate.
	soft_fail=1
}

cleanup_boot
