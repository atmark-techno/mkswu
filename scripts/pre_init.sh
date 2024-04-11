probe_current() {
	rootdev=$(swupdate -g)

	[ "${rootdev#mmcblk}" = "$rootdev" ] || rootdev="/dev/$rootdev"
	[ -e "$rootdev" ] || rootdev="$(findfs "$rootdev")"
	[ -e "$rootdev" ] || error "Could not find what partition linux booted from to guess what to flash"

	if [ "${rootdev##*[a-z]}" = "1" ]; then
		ab=1
	else
		ab=0
	fi
	partdev="${rootdev%[0-9]}"
	rootdev="$partdev"
	[ "${partdev#/dev/mmcblk}" = "$partdev" ] \
		|| rootdev="${partdev%p}"
}

init_vars() {
	local debug
	# override from sw-description
	debug=$(awk '/DEBUG_FLASH_DEV/ { print $NF }' "$SWDESC")
	if [ -n "$debug" ]; then
		rootdev="$debug"
		partdev="$rootdev"
		[ "${partdev#/dev/mmcblk}" = "$partdev" ] \
			|| partdev="${rootdev}p"
	fi
	debug=$(awk '/DEBUG_FLASH_AB/ { print $NF }' "$SWDESC")
	[ -n "$debug" ] && ab="$debug"

	if [ -z "$rootdev" ] || [ -z "$ab" ]; then
		probe_current
	fi

	# non-fatal if not present
	board=$(awk '{print $1; exit}' /etc/hwrevision 2>/dev/null)
}

init_vars_update() {
	if needs_update base_os; then
		update_rootfs=baseos
	elif needs_update_regex "extra_os.*" \
	    || [ -n "$(mkswu_var CONTAINER_CLEAR)" ]; then
		update_rootfs=1
	fi
	if update_rootfs || needs_update boot; then
		needs_reboot=1
	fi
	set_post_action
	if [ "$post_action" != "container" ]; then
		needs_reboot=1
	fi
	if [ -e "/etc/fw_env.config" ] \
	    && fw_printenv upgrade_available | grep -qx 'upgrade_available=1'; then
		upgrade_available=1
	fi
}

save_vars() {
	printf "%s\n" "$rootdev" > "$MKSWU_TMP/rootdev" \
		&& printf "%s\n" "$ab" > "$MKSWU_TMP/ab" \
		|| error "Could not save local variables"
	if needs_reboot; then
		touch "$MKSWU_TMP/needs_reboot" \
			|| error "Could not save need to reboot variable"
	fi
	if update_rootfs; then
		echo "$update_rootfs" > "$MKSWU_TMP/update_rootfs" \
			|| error "Could not save rootfs update variable"
	fi
}

fail_atmark_new_container() {
	local component
	# for tests
	local CONTAINER_CONF_DIR="${CONTAINER_CONF_DIR:-/etc/atmark/containers}"

	# Only check updates signed with atmark keys.
	# The binary public key is embedded in .sig (ASN1)
	local ATMARK_KEYS="3056301006072a8648ce3d020106052b8104000a034200048e06dddd223cfa2a1fdd32cbf6a4c636540df3856a90448f6774d25246148138842f7062d50a18cc6586a9f766acb88db20257e10037829682d7d43e7d63a410
3056301006072a8648ce3d020106052b8104000a0342000446444fe5e4d70531bbeb48049817c2073e1f5b261f531ddafac6321dee2e735b103766dabf17da065266c86238318fcf92387914355c75d65f8a5e79d9652859"
	xxd -p "$SWDESC.sig" | tr -d '\n' \
			| grep -qF "$ATMARK_KEYS" \
		|| return 0

	# we're clearing containers, so nothing to check
	[ -n "$(mkswu_var CONTAINER_CLEAR)" ] && return

	# base_os update: nothing to check
	[ -n "$(get_version base_os present)" ] && return

	# simple update? check if first version of swu had already been installed
	read -r component _ < "$MKSWU_TMP/sw-versions.present"
	[ -n "$(get_version "$component" old)" ] && return

	# We're installing a new container: only allow if no other container
	# is present
	if stat "$CONTAINER_CONF_DIR/"*.conf >/dev/null 2>/dev/null; then
		error "Refusing to install a new container from atmark official images" \
			"Please remove existing containers first with 'abos-ctrl container-clear'"
	fi
}

fail_redundant_update() {
	# if no version changed, clean up and fail script to avoid
	# downloading the rest of the image
	if [ -z "$(mkswu_var FORCE_VERSION)" ]; then
		if check_nothing_to_do; then
			rm -rf "$MKSWU_TMP"
			error "Nothing to do -- failing on purpose to save bandwidth"
		fi
		# also check B-side unless SW_ALLOW_ROLLBACK is set
		local dev="${partdev#/dev/}$((ab+1))"
		if [ -z "$SW_ALLOW_ROLLBACK" ] \
		    && [ -n "$upgrade_available" ] \
		    && cmp -s "/var/log/swupdate/sw-versions-$dev" "$MKSWU_TMP/sw-versions.merged"; then
			rm -rf "$MKSWU_TMP"
			error "Update looks like it already had been installed but rolled back, failing on purpose." \
				"Set SW_ALLOW_ROLLBACK=1 environment variable to force installing anyway."
		fi
	fi
}

init_custom_commands() {
	local action

	rm -f "$TMPDIR/swupdate_post_fail_action"

	action="$(mkswu_var NOTIFY_STARTING_CMD)"
	( eval "$action"; ) || error "NOTIFY_STARTING_CMD failed"

	action="$(mkswu_var NOTIFY_FAIL_CMD)"
	[ -z "$action" ] && return

	echo "$action" > "$TMPDIR/swupdate_post_fail_action"
	# swupdate does not provide any generic way of executing a command
	# after swupdate failure, or when it is over. . . But we can
	# rely on the fact that swupdate cleans up the scripts dir when
	# done, and that we will have removed post_fail_action file on
	# success, so we wait for that directory to disappear in a subprocess.
	(
		# inotifyd exits when it cannot watch anymore, but
		# we need to chdir out of it first...
		cd / || exit
		inotifyd - "$TMPDIR/scripts":x >/dev/null || exit
		[ -e "$TMPDIR/swupdate_post_fail_action" ] || exit 0
		sh "$TMPDIR/swupdate_post_fail_action"
		rm -f "$TMPDIR/swupdate_post_fail_action"
	) &
}

init_really_starting() {
	# if we got here we're really updating:
	# - signal we're starting an update if instructed
	# - handle a fail command if there is one
	# - mark the other partition as unbootable for rollback
	init_custom_commands

	# we won't be able to reboot into other partition until installer
	# finished; disable rollback
	if [ -e "/etc/fw_env.config" ]; then
		fw_setenv_nowarn upgrade_available
		case "$?" in
		0) ;; # ok
		243)
			# -EBADF usually means it tried to access default environment
			# This should normally never happen, but if the boot partition got
			# wiped out we should not leave swupdate unusable so try harder
			# to provide default env.
			grep -qE '^bootcmd=' /boot/uboot_env.d/* 2>/dev/null \
				|| error "Could not set u-boot environment variable and no default was provided, refusing to run"
			info "Could not set u-boot environment variable without defaults, retrying with a default file"
			cat /boot/uboot_env.d/* \
				| fw_setenv_nowarn --defenv - upgrade_available \
				|| error "Could not set u-boot environment variable, refusing to run"
			;;
		*)
			error "Could not set u-boot environment variable, refusing to run"
		esac
	fi
}

# when run in installer environment we skip most of the scripts
pre_installer() {
	gen_newversion
	needs_update base_os && error "Cannot update base OS in installer"
	needs_update boot && error "Cannot update boot image in installer"
}

init() {
	lock_update

	if [ -n "$SWUPDATE_FROM_INSTALLER" ]; then
		pre_installer
		exit 0
	fi

	cleanup

	init_vars
	gen_newversion
	init_vars_update

	fail_atmark_new_container
	fail_redundant_update
	printf "Using %s on boot %s. Reboot%s required.\n" "$rootdev" "$ab" \
		"$(needs_reboot || echo " not")"

	init_really_starting

	save_vars
}

[ -n "$TEST_SCRIPTS" ] && return

init
