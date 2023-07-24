post_success_rootfs() {
	# record last updated partition for abos-ctrl
	local newstate

	if ! [ -d "/var/log/swupdate" ] && ! mkdir /var/log/swupdate; then
		warning "Could not mkdir /var/log/swupdate"
		return
	fi

	if needs_reboot; then
		newstate="${partdev}$((ab+1))"
	else
		newstate="${partdev}$((!ab+1))"
		# no reboot means we updated other partition to our's, first.
		if [ -e "/var/log/swupdate/sw-versions-${newstate#/dev/}" ]; then
			mv "/var/log/swupdate/sw-versions-${newstate#/dev/}" \
					"/var/log/swupdate/sw-versions-${partdev#/dev/}$((ab+1))" \
				|| warning "Could not update latest sw-versions"
		fi
	fi

	echo "$newstate $(date +%s)" > "/var/log/swupdate/last_update" \
		|| warning "Could not record last update partition"
	cp "$SCRIPTSDIR/sw-versions.merged" "/var/log/swupdate/sw-versions-${newstate#/dev/}" \
		|| warning "Could not update latest sw-versions"
}

post_success_atlog() {
	# record update to atlog
	# in particular, we log:
	# - date
	# - destination partition
	# - updated versions
	local newstate
	local versions
	# variables for tests
	local atlog="${atlog:-/var/at-log/atlog}"
	local old_versions="${old_versions:-$SCRIPTSDIR/sw-versions.old}"
	local new_versions="${new_versions:-$SCRIPTSDIR/sw-versions.merged}"

	# if /var/at-log isn't mounted fallback to /var/log/swupdate/atlog
	if [ "$atlog" = "/var/at-log/atlog" ] && ! mountpoint -q /var/at-log; then
		atlog=/var/log/swupdate/atlog
	fi
	# if /var/log is encrypted also prefer /var/log
	local dev=$(findmnt -nr -o SOURCE /var/log)
	if [ -n "$dev" ] && [ "$(lsblk -n -o type "$dev")" = "crypt" ]; then
		atlog=/var/log/swupdate/atlog
	fi

	# rotate file if it got too big
	if [ "$(stat -c %s "$atlog" 2>/dev/null || echo 0)" -gt $((3*1024*1024)) ]; then
		mv -v "$atlog" "$atlog.1" \
			|| warning "Could not rotate atlog"
	fi

	if needs_reboot; then
		newstate="${partdev}$((ab+1))"
	else
		newstate="${partdev}$((!ab+1))"
	fi

	[ -e "$old_versions" ] || old_versions=/dev/null

	if ! versions="$(awk '
		newvers == 0 { oldv[$1]=$2 }
		newvers == 1 { newv[$1]=$2 }
		END {
			for (comp in newv) {
				old = oldv[comp] ? oldv[comp] : "unset";
				if (old != newv[comp])
					printf("%s: %s -> %s, ", comp, old, newv[comp]);
			}
			for (comp in oldv) {
				if (newv[comp] == "")
					printf("%s: %s -> unset, ", comp, oldv[comp]);
			}
		}' "$old_versions" newvers=1 "$new_versions")"; then
			warning "Could not compare new/old versions for atlog"
			versions="(could not compare versions)"
	fi
	versions="${versions%, }"

	[ -n "$versions" ] || versions="(no new version)"

	# HOSTNAME not posix sh
	[ -n "$HOSTNAME" ] || local HOSTNAME="$(hostname -s)"
	echo "$(date +"%b %_d %H:%M:%S") $HOSTNAME NOTICE swupdate: Installed update to $newstate: $versions" \
		>> "$atlog" \
		|| warning "Could not record update to atlog"
}

post_success_hawkbit() {
	# hawkbit service requires transmitting install status on next restart
	# /var/log is shared and not mounted on target
	touch /var/log/swupdate/hawkbit_install_done \
		|| warning "Could not create hawkbit install marker file"
}

post_success_usb() {
	# if the image is a force install image, move it to avoid install loop
	# we don't need to do this if the post action is poweroff, wait or container
	# as these have no risk of looping
	if [ -n "$(mkswu_var FORCE_VERSION)" ]; then
		POST_ACTION=$(post_action)
		case "$POST_ACTION" in
		poweroff|container|wait) ;;
		*) mv -v "$SWUPDATE_USB_SWU" "$SWUPDATE_USB_SWU.installed" \
			|| warning "Could not rename force version usb install image, might have a reinstall loop"
			;;
		esac
	fi
}

post_success_custom() {
	local action
	rm -f "$TMPDIR/swupdate_post_fail_action"
	action="$(mkswu_var NOTIFY_SUCCESS_CMD)"
	( eval "$action"; ) || error "NOTIFY_SUCCESS_CMD failed"
}

set_fw_update_ind() {
	local led_dir=/sys/class/leds/FW_UPDATE_IND

	[ -e "$led_dir/brightness" ] || return
	needs_reboot || return

	cat "$led_dir/max_brightness" > "$led_dir/brightness" \
		|| warning "Could not set FW_UPDATE_IND"
}

post_success() {
	post_success_rootfs
	post_success_atlog
	[ -n "$SWUPDATE_HAWKBIT" ] && post_success_hawkbit
	[ -n "$SWUPDATE_USB_SWU" ] && post_success_usb
	post_success_custom
	set_fw_update_ind
}

[ -n "$TEST_SCRIPTS" ] && return

post_success
