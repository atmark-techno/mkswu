enable_service() {
	local service="$1"
	local runlevel="$2"

	if [ -L "/target/etc/runlevels/$runlevel/$service" ] ||
	   ! [ -e "/target/etc/init.d/$service" ]; then
		return
	fi

	ln -sf "/etc/init.d/$service" "/target/etc/runlevels/$runlevel/" \
		|| error "could not enable $service service"
}

disable_service() {
	local service="$1"
	local runlevel="$2"

	rm -f "/target/etc/runlevels/$runlevel/$service"
}

baseos_upgrade_fixes() {
	local baseos_version overlays

	# if user has local certificates we should regenerate the bundle
	if stat /target/usr/local/share/ca-certificates/* >/dev/null 2>&1; then
		FILTER="WARNING: ca-certificates.crt does not contain exactly one certificate or CRL: skipping" \
			podman_info run --net=none --rootfs /target update-ca-certificates 2>/dev/null \
				|| error "update-ca-certificates failed"
	fi

	### workaround section, these can be removed once we consider we no longer
	### support a given version.

	# note this is the currently running version,
	# not the version we install (which would always be too recent!)
	baseos_version=$(cat /etc/atmark-release) || return

	# not a baseos install? skip fixes...
	[ -n "$baseos_version" ] || return

	# add /var/at-log to fstab (added in 3.15.0-at.1)
	if grep -q /dev/mmcblk2 /proc/cmdline \
	    && [ -e /dev/mmcblk2gp1 ] \
	    && ! grep -q /dev/mmcblk2gp1 /target/etc/fstab; then
		cat >> /target/etc/fstab <<'EOF' \
			|| error "Could not append to target /etc/fstab"
/dev/mmcblk2gp1	/var/at-log			vfat	defaults			0 0
EOF
	fi

	# add noatime to fstab (added in 3.15.0-at.2)
	if ! grep -q noatime /target/etc/fstab; then
		sed -i -e '/squashfs/ ! s/defaults/&,noatime/' \
				-e 's/,subvol=/,noatime&/' /target/etc/fstab \
			|| error "Could not update fstab"
	fi

	# Remove /var/log/rc.log we no longer write to
	# (removed in 3.15.4-at.6)
	if [ -e /var/log/rc.log ]; then
		rm -f /var/log/rc.log
	fi

	# Increase swupdate.cfg verbosity
	# (done in 3.16-at.1)
	if grep -q 'loglevel = 2;' /target/etc/swupdate.cfg; then
		sed -i -e 's/loglevel = 2/loglevel = 3/' /target/etc/swupdate.cfg \
			|| error "Could not update swupdate.cfg"
	fi

	# Restore modemmanager/wwan services if required,
	# and add new wwan-safe-shutdown as well in this case
	# (preserve_files fixed in 3.16.2-at.6 // mkswu 1.8)
	overlays="$(awk -F= '$1 == "fdt_overlays" { print $2 }' /boot/overlays.txt 2>/dev/null)"
	case " $overlays " in
	*" armadillo_iotg_g4-lte-ext-board.dtbo "*)
		# G4 LTE - mm is started from udev rule
		disable_service modemmanager boot
		enable_service wwan-safe-poweroff shutdown
		;;
	*" armadillo-iotg-a6e-els31.dtbo "*)
		# A6E Cat.1
		enable_service modemmanager boot
		enable_service wwan-safe-poweroff shutdown
		enable_service wwan-led default
		;;
	*" armadillo-iotg-a6e-ems31.dtbo "*)
		# A6E Cat.M1
		enable_service ems31-boot boot
		enable_service wwan-safe-poweroff shutdown
		enable_service wwan-led default
		;;
	esac
	# Enable wifi-recover, only for wifi-enabled boards if the
	# service just got added to allow for users disabling it.
	# (added in 3.16.2-at.6)
	case " $overlays " in
	*" armadillo_iotg_g4-aw-xm458.dtbo "*)
		if ! [ -e /target/etc/init.d/wifi-recover ]; then
			enable_service wifi-recover default
		fi
		;;
	esac

	# correct URL in /etc/swupdate.watch
	local target_for_x2="https://download.atmark-techno.com/armadillo-iot-g4/image/baseos-x2-latest.swu"
	if [ "$(cat /target/etc/swupdate.watch)" = "$target_for_x2" ]; then
		case "$(cat /etc/hwrevision)" in
		iot-a6e*) sed -i -e 's/g4/a6e/; s/x2/6e/' /target/etc/swupdate.watch;;
		AX2210*) sed -i -e 's/iot-g4/x2/' /target/etc/swupdate.watch;;
		esac || error "Could not update swupdate.watch"
	fi
	case "$(cat /etc/hwrevision)" in
	iot-a6e*)
		local gw_container_conf="/target/etc/atmark/containers/a6e-gw-container.conf"
		local target_for_a6e_baseos="https://download.atmark-techno.com/armadillo-iot-a6e/image/baseos-6e-latest.swu"
		local target_for_a6e_gw_container="https://download.atmark-techno.com/armadillo-iot-a6e/image/a6e-gw-container-latest.swu"
		if grep -qE '^image="a6e-gw-container[:"]' "$gw_container_conf" 2>/dev/null \
		    && grep -qxF 'set_image "$image"' "$gw_container_conf" \
		    && grep -qxF "$target_for_a6e_baseos" /target/etc/swupdate.watch 2>/dev/null \
		    && ! grep -qxF "$target_for_a6e_gw_container" /target/etc/swupdate.watch; then
			echo "$target_for_a6e_gw_container" >> /target/etc/swupdate.watch \
				|| error "Could not update swupdate.watch"
		fi
		;;
	esac
}

baseos_upgrade_fixes
