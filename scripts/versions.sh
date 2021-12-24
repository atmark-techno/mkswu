get_version() {
	local install_if=""
	if [ "$1" = "--install-if" ]; then
		install_if=1
		shift
	fi
	local component="$1"
	local source="${2:-$SCRIPTSDIR/sw-versions.present}"

	[ -e "$source" ] || return

	awk '$1 == "'"$component"'" { print $2'"${install_if:+, \$3}"' }' < "$source"
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
	local install_if="$1"
	local oldvers="$2"
	local newvers="$3"

	[ -n "$newvers" ] || return 1

	case "$install_if" in
	different) [ "$newvers" != "$oldvers" ];;
	higher) version_higher "$oldvers" "$newvers";;
	*) error "unexpected update install_if $install_if";;
	esac
}

needs_update() {
	local component="$1"
	local newvers oldvers install_if
	local system_versions="${system_versions:-/etc/sw-versions}"

	newvers=$(get_version --install-if "$component")
	[ -n "$newvers" ] || return 1
	install_if=${newvers##* }
	newvers=${newvers% *}

	oldvers=$(get_version "$component" "$system_versions")
	version_update "$install_if" "$oldvers" "$newvers"
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

extract_swdesc_versions() {
	# extract version comments
	sed -ne "s/.*#VERSION //p"
}

gen_newversion() {
	local component oldvers newvers install_if
	local system_versions="${system_versions:-/etc/sw-versions}"

	extract_swdesc_versions < "$SWDESC" > "$SCRIPTSDIR/sw-versions.present"

	if ! [ -e "$system_versions" ]; then
		sed -e 's/^[^ ]* //' "$SCRIPTSDIR/sw-versions.present" \
			> "$SCRIPTSDIR/sw-versions.merged"
		return
	fi

	# Merge files, keeping order of original sw-versions,
	# then appending other lines from new one in order as well.
	# Could probably do better but it works and files are small..
	while read -r component oldvers; do
		case "$component" in
		other_boot) continue;;
		boot) printf "%s\n" "other_boot $oldvers";;
		esac
		newvers=$(get_version --install-if "$component")
		install_if=${newvers##* }
		newvers=${newvers% *}
		version_update "$install_if" "$oldvers" "$newvers" || newvers="$oldvers"
		printf "%s\n" "$component $newvers"
	done < "$system_versions" > "$SCRIPTSDIR/sw-versions.merged"
	while read -r component newvers install_if; do
		oldvers=$(get_version "$component" "$system_versions")
		[ -z "$oldvers" ] && printf "%s\n" "$component $newvers"
	done < "$SCRIPTSDIR/sw-versions.present" >> "$SCRIPTSDIR/sw-versions.merged"
}
