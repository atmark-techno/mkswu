get_version() {
	local component="$1"
	local source="${2:-$SCRIPTSDIR/sw-versions.present}"

	[ -e "$source" ] || return

	awk '$1 == "'"$component"'" { print $2 }' < "$source"
}

# strict greater than
version_higher() {
	local oldvers="$1"
	local newvers="$2"

	! echo -e "$2\n$1" | sort -VC
}

version_update() {
	local component="$1"
	local oldvers="$2"
	local newvers="$3"

	[ -n "$newvers" ] || return 1

	case "$component" in
	uboot|kernel) [ "$newvers" != "$oldvers" ];;
	*) version_higher "$oldvers" "$newvers";;
	esac
}

needs_update() {
	local component="$1"
	local newvers oldvers

	newvers=$(get_version "$component")
	[ -n "$newvers" ] || return 1

	oldvers=$(get_version "$component" /etc/sw-versions)
	version_update "$component" "$oldvers" "$newvers"
}

needs_reboot() {
	[ -n "$needs_reboot" ]
}

parse_swdesc() {
	# extract all present component versions then keep whatever is biggest
	awk -F'[" ]+' '$2 == "name" {component=$4}
		component && $2 == "version" { print component, $4 }
		/,/ { component="" }' |
		sort -Vr | sort -u -k 1,1
}

gen_newversion() {
	local component oldvers newvers

	parse_swdesc < "$SWDESC" > "$SCRIPTSDIR/sw-versions.present"

	if ! [ -e "/etc/sw-versions" ]; then
		cp "$SCRIPTSDIR/sw-versions.present" "$SCRIPTSDIR/sw-versions.merged"
		return
	fi

	# Merge files, keeping order of original sw-versions,
	# then appending other lines from new one in order as well.
	# Could probably do better but it works and files are small..
	while read -r component oldvers; do
		[ "$component" = "other_uboot" ] && continue
		if [ "$component" = "uboot" ]; then
			echo "other_uboot $oldvers"
		fi
		newvers=$(get_version "$component")
		version_update "$component" "$oldvers" "$newvers" || newvers="$oldvers"
		echo "$component $newvers"
	done < /etc/sw-versions > "$SCRIPTSDIR/sw-versions.merged"
	while read -r component newvers; do
		oldvers=$(get_version "$component" /etc/sw-versions)
		[ -z "$oldvers" ] && echo "$component $newvers"
	done < "$SCRIPTSDIR/sw-versions.present" >> "$SCRIPTSDIR/sw-versions.merged"

	# if no version changed, clean up and fail script to avoid
	# downloading the rest of the image
	if cmp -s /etc/sw-versions "$SCRIPTSDIR/sw-versions.merged"; then
		rm -rf "$SCRIPTSDIR"
		error "Nothing to do -- failing on purpose to save bandwidth"
	fi

}

update_running_versions() {
	mv "$1" /etc/sw-versions || error "Could not update /etc/sw-versions"

	[ "$(stat -f -c %T /etc/sw-versions)" = "overlayfs" ] || return

	# bind-mount / somewhere else to write below it as well
	mount --bind / /target || error "Could not bind mount rootfs"
	mount -o remount,rw /target || error "Could not make rootfs rw"
	cp /etc/sw-versions /target/etc/sw-versions || error "Could not write $1 to /etc/sw-versions"
	umount /target || error "Could not umount rootfs rw copy"
}
