post_success_rootfs() {
	# record last updated partition for abos-ctrl
	local newstate

	if needs_reboot; then
		newstate="${partdev}$((ab+1))"
	else
		newstate="${partdev}$((!ab+1))"
	fi

	echo "$newstate $(date +%s)" > "/var/log/swupdate/last_update" \
		|| warning "Could not record last update partition"
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
	local old_versions="${old_versions:-/etc/sw-versions}"
	local new_versions="${new_versions:-$SCRIPTSDIR/sw-versions.merged}"

	# if /var/at-log isn't mounted fallback to /var/log/swupdate/atlog
	if [ "$atlog" = "/var/at-log/atlog" ] && ! mountpoint -q /var/at-log; then
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
		old_versions="/target/$old_versions"
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

	echo "$(date +"%b %_d %H:%M:%S") $HOSTNAME NOTICE swupdate: Installed update to $newstate: $versions" \
		>> "$atlog" \
		|| warning "Could not record update to atlog"
}

post_success_hawkbit() {
	# hawkbit service requires transmitting install status on next restart
	local dev="${partdev}5"
	local basemount newstate

	# /var/log is shared and not mounted on target
	touch /var/log/swupdate/hawkbit_install_done \
		|| warning "Could not create hawkbit install marker file"

	# The following is no longer required from atmark-x2-base 1.4 onwards
	# We should theorically check apk version, but that is slow,
	# so check abos-ctrl command exitance instead.
	# Note we check on current OS, not updated one: this is because
	# we need this to work in case of failed update.
	# XXX add cleanup of subvolume in post root fixup when we remove this
	[ -e /usr/sbin/abos-ctrl ] && return

	basemount=$(mktemp -d -t btrfs-swupdate.XXXXXX) || warning "Could not create temp dir"
	if ! mount -t btrfs -o subvol=/swupdate "$dev" "$basemount" 2>/dev/null; then
		mount -o subvol=/ "$dev" "$basemount" || warning "Could not mount app root"
		btrfs subvolume create "$basemount/swupdate" || warning "Could not create swupdate subvolume"
		umount "$basemount" || warning "Could not umount app root"
		mount -o subvol=/swupdate "$dev" "$basemount" || warning "Could not mount swupdate subvolume"
	fi

	if needs_reboot; then
		newstate="${partdev}$((ab+1))"
	else
		newstate="${partdev}$((!ab+1))"
	fi

	echo "$newstate" > "$basemount/updated-rootfs" || warning "Could not write success file"
	umount "$basemount" || warning "Could not umount swupdate subvolume"
	rmdir "$basemount"
}

post_success_usb() {
	# if the image is a force install image, move it to avoid install loop
	# we don't need to do this if the post action is poweroff
	if grep -q FORCE_VERSION "$SWDESC" \
	    && ! grep -q POSTACT_POWEROFF "$SWDESC"; then
		mv -v "$SWUPDATE_USB_SWU" "$SWUPDATE_USB_SWU.installed" \
			|| echo "Could not rename force version usb install image, might have a reinstall loop" >&2
	fi
}

set_fw_update_ind() {
	local led_dir=/sys/class/leds/FW_UPDATE_IND

	[ -e "$led_dir/brightness" ] || return
	needs_reboot || return

	# It's too late to fail, but try to warn if we couldn't set led
	cat "$led_dir/max_brightness" > "$led_dir/brightness" \
		|| echo "Could not set FW_UPDATE_IND" >&2
}

post_success() {
	[ -d "/var/log/swupdate" ] || mkdir /var/log/swupdate \
		|| warning "Could not mkdir /var/log/swupdate"
	post_success_rootfs
	post_success_atlog
	[ -n "$SWUPDATE_HAWKBIT" ] && post_success_hawkbit
	[ -n "$SWUPDATE_USB_SWU" ] && post_success_usb
	set_fw_update_ind
}

[ -n "$TEST_SCRIPTS" ] && return

post_success
