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
	local oldpredash newpredash
	local oldhasdash="" newhasdash=""

	oldpredash=${oldvers%%-*}
	newpredash=${newvers%%-*}
	if [ "$oldpredash" = "$newpredash" ]; then
		# swupdate compares version as semver which says x.y.z > x.y.z-t
		# if only either of the two component have a dash *and*
		# the prefix part before the only dash is the same, override
		# sort -V result here.
		[ "$oldpredash" != "$oldvers" ] && oldhasdash="1"
		[ "$newpredash" != "$newvers" ] && newhasdash="1"

		case "$oldhasdash,$newhasdash" in
		0,1) return 0;;
		1,0) return 1;;
		esac
	fi

	! printf "%s\n" "$2" "$1" | sort -VC
}

version_update() {
	local component="$1"
	local oldvers="$2"
	local newvers="$3"

	[ -n "$newvers" ] || return 1

	case "$component" in
	boot) [ "$newvers" != "$oldvers" ];;
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

needs_update_regex() {
	# returns true if any need update, false if all fail
	local regex="$1"
	local component

	for component in $(awk '$1 ~ /^'"$regex"'$/ { print $1 }' "$SCRIPTSDIR/sw-versions.present"); do
		needs_update "$component" && return
	done
	return 1
}

needs_reboot() {
	[ -n "$needs_reboot" ]
}

update_rootfs() {
	[ -n "$update_rootfs" ]
}

parse_swdesc() {
	# extract version comments
	sed -ne "s/.*#VERSION //p"
}

gen_newversion() {
	local component oldvers newvers
	local base_os

	parse_swdesc < "$SWDESC" > "$SCRIPTSDIR/sw-versions.present"

	if ! [ -e "/etc/sw-versions" ]; then
		cp "$SCRIPTSDIR/sw-versions.present" "$SCRIPTSDIR/sw-versions.merged"
		return
	fi

	needs_update "base_os" && base_os=1

	# Merge files, keeping order of original sw-versions,
	# then appending other lines from new one in order as well.
	# Could probably do better but it works and files are small..
	while read -r component oldvers; do
		case "$component" in
		other_boot) continue;;
		boot) printf "%s\n" "other_boot $oldvers";;
		extra_os*) [ -n "$base_os" ] && continue;;
		esac
		newvers=$(get_version "$component")
		version_update "$component" "$oldvers" "$newvers" || newvers="$oldvers"
		printf "%s\n" "$component $newvers"
	done < /etc/sw-versions > "$SCRIPTSDIR/sw-versions.merged"
	while read -r component newvers; do
		oldvers=$(get_version "$component" /etc/sw-versions)
		if [ -n "$base_os" ] && [ "${component#extra_os}" != "$component" ]; then
			# extra_os likely won't be installed, skip for next run
			# in genral extra_os and base_os shouldn't be mixed anyway
			needs_update "$component" || continue
		fi
		[ -z "$oldvers" ] && printf "%s\n" "$component $newvers"
	done < "$SCRIPTSDIR/sw-versions.present" >> "$SCRIPTSDIR/sw-versions.merged"

	# if no version changed, clean up and fail script to avoid
	# downloading the rest of the image
	if cmp -s /etc/sw-versions "$SCRIPTSDIR/sw-versions.merged" \
	    && ! grep -q "#FORCE_VERSION" "$SWDESC"; then
		rm -rf "$SCRIPTSDIR"
		error "Nothing to do -- failing on purpose to save bandwidth"
	fi

}

update_running_versions() {
	cp "$1" /etc/sw-versions || error "Could not update /etc/sw-versions"

	[ "$(stat -f -c %T /etc/sw-versions)" = "overlayfs" ] || return

	# bind-mount / somewhere else to write below it as well
	mount --bind / /target || error "Could not bind mount rootfs"
	mount -o remount,rw /target || error "Could not make rootfs rw"
	cp /etc/sw-versions /target/etc/sw-versions || error "Could not write $1 to /etc/sw-versions"
	umount /target || error "Could not umount rootfs rw copy"
}
