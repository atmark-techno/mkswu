get_version() {
	local install_if=""
	if [ "$1" = "--install-if" ]; then
		install_if=1
		shift
	fi
	local component="$1"
	local source="$SCRIPTSDIR/sw-versions.${2:-merged}"

	[ -e "$source" ] || return

	# We need to handle two different file syntaxes here:
	# - installed version files, "component version"
	# - versions from sw-description, "component version install_if board"
	# If board is set we need to not print default version so this requires
	# remembering all versions for this component and printing the right one
	# It is an error to request install-if on installed version files
	# (but we don't enforce that check)
	awk '$1 == "'"$component"'" {
			if (NF == 2) { print $2; exit; }
			board[$4]=$2'"${install_if:+ \" \"  \$3}"'
		}
		END {
			if (board["'"$board"'"]) {
				print board["'"$board"'"];
			} else if (board["*"]) {
				print board["*"];
			}
		}' < "$source"
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

	newvers=$(get_version --install-if "$component" present)
	[ -n "$newvers" ] || return 1
	install_if=${newvers##* }
	newvers=${newvers% *}

	oldvers=$(get_version "$component" old)
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
	local component oldvers newvers install_if newvers_board
	local system_versions="${system_versions:-/etc/sw-versions}"
	[ -e "$system_versions" ] || system_versions=/dev/null

	if [ -e "$system_versions" ]; then
		cp "$system_versions" "$SCRIPTSDIR/sw-versions.old" \
			|| error "Could not copy existing versions"
	fi

	extract_swdesc_versions < "$SWDESC" > "$SCRIPTSDIR/sw-versions.present" \
		|| error "Could not extract versions present in swdesc"

	# Merge files, keeping order of original sw-versions,
	# then appending other lines from new one in order as well.
	# Could probably do better but it works and files are small..
	awk '!filter[$1] { filter[$1]=1; print }' "$system_versions" \
		| while read -r component oldvers; do
			case "$component" in
			other_boot) continue;;
			boot) printf "%s\n" "other_boot $oldvers";;
			other_boot_linux) continue;;
			boot_linux) printf "%s\n" "other_boot_linux $oldvers";;
			esac
			newvers=$(get_version --install-if "$component" present)
			install_if=${newvers##* }
			newvers=${newvers% *}
			version_update "$install_if" "$oldvers" "$newvers" \
				|| newvers="$oldvers"
			printf "%s\n" "$component $newvers"
		done > "$SCRIPTSDIR/sw-versions.merged" \
		|| error "Version generation from current versions failed"
	while read -r component newvers install_if newvers_board; do
		case "$newvers_board" in
		"*"|"$board") ;;
		*) continue;;
		esac
		oldvers=$(get_version "$component" old)
		[ -n "$oldvers" ] || printf "%s\n" "$component $newvers"
	done < "$SCRIPTSDIR/sw-versions.present" >> "$SCRIPTSDIR/sw-versions.merged" \
		|| error "Version generation from new versions in swu failed"
}
