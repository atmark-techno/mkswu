post_success_rootfs() {
	# record last updated partition for abos-ctrl
	local newpart oldpart

	if needs_reboot; then
		newpart="${partdev}$((ab+1))"
		oldpart="${partdev}$((!ab+1))"
	else
		newpart="${partdev}$((!ab+1))"
		oldpart="${partdev}$((ab+1))"
	fi

	echo "$newpart $(date +%s)" > "/var/log/swupdate/last_update" \
		|| warning "Could not record last update partition"
	cp "$MKSWU_TMP/sw-versions.merged" "/var/log/swupdate/sw-versions-${newpart#/dev/}" \
		|| warning "Could not update latest sw-versions"
	cp "$MKSWU_TMP/sw-versions.init" "/var/log/swupdate/sw-versions-${oldpart#/dev/}" \
		|| warning "Could not update previous sw-versions"
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
	local old_versions="${old_versions:-$MKSWU_TMP/sw-versions.init}"
	local new_versions="${new_versions:-$MKSWU_TMP/sw-versions.merged}"

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
	# transmit install status on mandatory service restart
	touch /var/log/swupdate/hawkbit_install_done \
		|| warning "Could not create hawkbit install marker file"
}

post_success_armadillo_twin() {
	# transmit install status on next boot -- skip if not rebooting
	[ "$post_action" = container ] && return
	echo "$SWUPDATE_ARMADILLO_TWIN" > /var/log/swupdate/armadillo_twin_install_done \
		|| warning "Could not create armadillo twin install marker file"
}

post_success_usb() {
	# if the image is a force install image, move it to avoid install loop
	# we don't need to do this if the post action is poweroff, wait or container
	# as these have no risk of looping
	if [ -n "$(mkswu_var FORCE_VERSION)" ]; then
		case "$post_action" in
		poweroff|container|wait) ;;
		*) mv -v "$SWUPDATE_USB_SWU" "$SWUPDATE_USB_SWU.installed" \
			|| warning "Could not rename force version usb install image, might have a reinstall loop"
			;;
		esac
	fi
}

post_success_custom() {
	local action

	if [ -z "$SWUPDATE_VERSION" ]; then
		# file was not created on swupdate >= 2023.12
		rm -f "$TMPDIR/.swupdate_post_fail_action.$PPID"
	fi

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
	if ! [ -d "/var/log/swupdate" ] && ! mkdir /var/log/swupdate; then
		warning "Could not create /var/log/swupdate"
	fi

	post_success_rootfs
	post_success_atlog
	set_post_action
	[ -n "$SWUPDATE_HAWKBIT" ] && post_success_hawkbit
	[ -n "$SWUPDATE_ARMADILLO_TWIN" ] && post_success_armadillo_twin
	[ -n "$SWUPDATE_USB_SWU" ] && post_success_usb
	post_success_custom
	set_fw_update_ind
	log_status "SUCCESS"
}

[ -n "$TEST_SCRIPTS" ] && return

post_success
