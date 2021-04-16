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

gen_newversion() {
	local component oldvers newvers

	# extract all present component versions then keep whatever is biggest
	awk -F'[" ]+' '$2 == "name" {component=$4}
		component && $2 == "version" { print component, $4 }
		/,/ { component="" }' < "$TMPDIR/sw-description" |
		sort -Vr | sort -u -k 1,1 > "$SCRIPTSDIR/sw-versions.present"

	if ! [ -e "/etc/sw-versions" ]; then
		cp "$SCRIPTSDIR/sw-versions.present" "$SCRIPTSDIR/sw-versions.merged"
		return
	fi

	# Merge files, keeping order of original sw-versions,
	# then appending other lines from new one in order as well.
	# Could probably do better but it works and files are small..
	while read -r component oldvers; do
		if [ "$component" = "other_uboot" ]; then
			newvers=$(get_version "uboot" /etc/sw-versions)
			[ -n "$newvers" ] && echo "other_uboot $newvers"
			continue
		fi
		newvers=$(get_version "$component")
		version_update "$component" "$oldvers" "$newvers" || newvers="$oldvers"
		echo "$component $newvers"
	done < /etc/sw-versions > "$SCRIPTSDIR/sw-versions.merged"
	while read -r component newvers; do
		oldvers=$(get_version "$component" /etc/sw-versions)
		[ -z "$oldvers" ] && echo "$component $newvers"
	done < "$SCRIPTSDIR/sw-versions.present" >> "$SCRIPTSDIR/sw-versions.merged"

	# if no version changed, signal it and bail out
	if cmp -s /etc/sw-versions $SCRIPTSDIR/sw-versions.merged; then
		touch "$SCRIPTSDIR/nothing_to_do"
		exit 0
	fi

}

update_running_versions() {
        # atomic update for running sw versions
        mount --bind / /target || error "Could not bind mount rootfs"
        mount -o remount,rw /target || error "Could not make rootfs rw"
        mv "$1" /target/etc/sw-versions || error "Could not write $1 to /etc/sw-versions"
        umount /target || error "Could not umount rootfs rw copy"
}
