# SPDX-License-Identifier: MIT

allow_upgrade_available() {
	# Do not set upgrade_available if other boot is encrypted,
	# we would not be able to boot into it.
	[ -z "$encrypted_boot" ] || return

	# Cannot fw_setenv without this...
	# Note we're setting current's env after target has been unmounted!
	[ -s /etc/fw_env.config ] || return

	# Do not set upgrade_available if it is not set in default
	# configuration.
	cat /boot/uboot_env.d/* 2>/dev/null | awk -F= '
		/^upgrade_available=/ { val=$2 }
		END { if (val == "") exit(1); }'
}

cleanup_target() {
	sync
	cleanup success

	# Mark other fs as usable again unless encrypted boot is used
	if allow_upgrade_available; then
		# always set 0: we don't know if what we just installed works,
		# so it's available, but not a target for auto rollback.
		fw_setenv_nowarn upgrade_available 0 \
			|| warn "could not restore upgrade_available"
	fi
}

workaround_a600_mmc() {
	# old Armadillo 640 eMMC is broken and issuing a bootpart change without
	# a switch to mmcblk0bootX partition is known to cause corruptions
	# The dd forces the hardware to issue such a switch, and fsfreeze ensures
	# no other writes are done in between
	[ "$(get_mmc_name)" = Q2J55L ] || return

	if command -v fsfreeze >/dev/null; then
		fsfreeze=1
		fsfreeze -f /var/app/volumes
		fsfreeze -f /var/log
	fi

	dd if="${rootdev}boot0" of=/dev/null bs=4k count=1 iflag=direct status=none
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
			if (! (start+0)) exit(1);
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
		conv=fsync status=none
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
}

cleanup_boot() {
	local encrypted_boot="" fsfreeze="" fail=""

	if ! needs_reboot; then
		cleanup_target
		return
	fi

	if [ -e /target/etc/fw_env.config ] \
	    && fw_printenv dek_spl_offset | grep -q dek_spl_offset=0x; then
		encrypted_boot=1
	fi

	# if uboot was installed, try to safeguard against u-boot
	# installed on incompatible arch.
	# This is not strictly enough but should prevent most complete
	# bricks from installing an incompatible SWU...
	if [ -e "$MKSWU_TMP/boot_updated" ] \
	    && [ -z "$(mkswu_var NO_ARCH_CHECK)" ]; then
		case "$(uname -m)" in
		aarch64)
			local expect="" board
			case "$(tr -d '\0' < /sys/firmware/devicetree/base/compatible 2>/dev/null)" in
			*imx8ulp*)
				expect=00200287
				board=i.MX8ULP
				;;
			*imx8mp*)
				expect=d1002041
				board=i.MX8MP
				;;
			*)
				warning "Did not recognize board, not checking u-boot validity"
				;;
			esac
			[ -z "$expect" ] \
				|| [ "$(xxd -l 4 -p /dev/swupdate_bootdev)" = "$expect" ] \
				|| error "Installed u-boot does not appear to be for $board, aborting!" \
					"In case of false positive, set MKSWU_NO_ARCH_CHECK=1"
			;;
		armv7*)
			[ "$(xxd -l 4 -p -s 1024 /dev/swupdate_bootdev)" = d1002040 ] \
				|| error "Installed u-boot does not appear to be for armv7, aborting!" \
					"In case of false positive, set MKSWU_NO_ARCH_CHECK=1"
			;;
		esac
	fi

	# for SD cards, we stored uboot in a temporary file and need to copy it now
	if [ -f /dev/swupdate_bootdev ]; then
		local skip=0 seek=0
		case "$(uname -m)" in
		aarch64)
			seek=$((32*1024))
			;;
		armv7*)
			seek=1024
			skip=1024
			;;
		*)
			error "boot image updates is only supported on aarch64/armv7"
			;;
		esac

		dd if=/dev/swupdate_bootdev of="$rootdev" bs=1M \
				iflag=skip_bytes skip="$skip" \
				oflag=seek_bytes seek="$seek" \
				status=none conv=fsync \
			|| error "Could not copy boot image, aborting! In case of partial copy the system might be unbootable!!"
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
			workaround_a600_mmc
			echo "setting mmc bootpart enable $((ab+1))"
			mmc bootpart enable "$((ab+1))" 0 "$rootdev" || fail=1
			if [ -n "$fsfreeze" ]; then
				# there apparently can still be problems if we write immediately
				# after bootpart as well, 1s seems to be enough to avoid issues.
				sleep 1
				fsfreeze -u /var/app/volumes
				fsfreeze -u /var/log
			fi
			[ -z "$fail" ] || error "Could not flip mmc boot flag"
		fi
	elif [ -s /target/etc/fw_env.config ]; then
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
