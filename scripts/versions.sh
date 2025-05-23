get_version() {
	local install_if=""
	if [ "$1" = "--install-if" ]; then
		install_if=1
		shift
	fi
	local component="$1"
	local source="$MKSWU_TMP/sw-versions.${2:-merged}"

	[ -e "$source" ] || return

	# We need to handle two different file syntaxes here:
	# - installed version files, "component version"
	# - versions from sw-description, "component version install_if board"
	# - ... and versions from older sw-descriptions, "component version" where
	#   we need to make up install_if if required
	# If board is set we need to not print default version so this requires
	# remembering all versions for this component and printing the right one
	# It is an error to request install-if on installed version files
	# (but we don't enforce that check)
	# Lastly, swupdate ignores leading 0 and (trailing .0 in main version),
	# so we need to filter that out too with simplify_version helper
	awk -v "component=$component" -v "board=${board:-none}" \
		-v "install_if=$install_if" \
		'$1 == component {
			if (!$4) { $4="*" }
			found[$4]=$2
			if (install_if) {
				if (!$3) {
					# use defaults: higher for all except boot
					$3 = component == "boot" ? "different" : "higher"
				}
				found[$4]=found[$4] " " $3
			}
		}
		END {
			if (found[board] != "") {
				print(found[board]);
			} else if (found["*"] != "") {
				print(found["*"]);
			}
		}' < "$source"
}

# strict greater than
version_higher() {
	local oldvers="${1%+*}"
	local newvers="${2%+*}"
	local oldpredash newpredash
	local oldhasdash="" newhasdash=""

	oldpredash=${oldvers%%-*}
	newpredash=${newvers%%-*}
	if [ "$oldpredash" = "$newpredash" ]; then
		# swupdate compares version as semver which says x.y.z > x.y.z-t
		# (which is not native sort -V order)
		# If only either of the two component have a dash *and*
		# the prefix part before the only dash is the same, override
		# sort -V result here.
		[ "$oldpredash" != "$oldvers" ] && oldhasdash="1"
		[ "$newpredash" != "$newvers" ] && newhasdash="1"

		case "$oldhasdash,$newhasdash" in
		,1) return 1;;
		1,) return 0;;
		esac
	fi

	! printf "%s\n" "$newvers" "$oldvers" | sort -Vc 2>/dev/null
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

	for component in $(awk '$1 ~ /^'"$regex"'$/ { print $1 }' "$MKSWU_TMP/sw-versions.present"); do
		needs_update "$component" && return
	done
	return 1
}

extract_swdesc_versions() {
	# also fix boot versions: remove leading zero, add dot after -at
	sed -n  -e 's/\(VERSION boot 20[0-9][0-9]\).0\([0-9]\)/\1.\2/' \
		-e 's/\(VERSION boot 20[0-9][0-9].[0-9]\+-at\)\([0-9]\)/\1.\2/' \
		-e "s/.*#VERSION //p"
}

fix_boot_versions() {
	[ "$component" != boot ] && return

	# fix old boot versions

	# 2020.04 -> 2020.4 (newer versions are correct so only 2020.4 is needed)
	[ "$oldvers" != "${oldvers#2020.04}" ] \
		&& oldvers="2020.4${oldvers#2020.04}"

	# 2020.4-at24 -> 2020.4-at.24
	if [ "$oldvers" != "${oldvers#20*-at[0-9]}" ]; then
		local tmpvers="${oldvers%%-at*}-at.${oldvers#20*-at}"
		# We fix sw-versions' "boot" entry on any installed SWU,
		# but any real update won't happen because swupdate itself does not
		# know about this (at.24 < at20 for swupdate)
		# In particular, we do NOT want $newvers in new sw-versions!
		# The worst that can happen if we get this wrong is new version gets
		# installed twice.
		if [ "$install_if" = higher ] \
		    && version_update higher "$tmpvers" "$newvers"; then
			warning "'boot' version format was updated ($oldvers -> $tmpvers), but $newvers has" \
				"NOT been installed! Please install this SWU again to update boot image."
			# also "unfix" sw-versions.old to make sure this is installed
			# even if nothing else is planned
			sed -i -e 's/^\(boot .*-at\)\./\1/' "$MKSWU_TMP/sw-versions.old"
			newvers=""
		fi
		oldvers="$tmpvers"
	fi
}

check_nothing_to_do() {
	cmp -s "$MKSWU_TMP/sw-versions.old" "$MKSWU_TMP/sw-versions.merged"
}

gen_newversion() {
	local component oldvers newvers install_if newvers_board
	local system_versions="${system_versions:-/etc/sw-versions}"
	[ -e "$system_versions" ] || system_versions=/dev/null

	# If the system still contains an old boot version with 0-padding
	# then remove padding here to avoid incorrect update detections
	sed		-e 's/^\(boot 20[0-9][0-9]\).0\([0-9]\)/\1.\2/' \
			-e 's/^\(boot 20[0-9][0-9].[0-9]\+-at\)\([0-9]\)/\1.\2/' \
			< "$system_versions" \
			> "$MKSWU_TMP/sw-versions.old" \
		|| error "Could not copy existing versions"

	extract_swdesc_versions < "$SWDESC" > "$MKSWU_TMP/sw-versions.present" \
		|| error "Could not extract versions present in swdesc"

	# Merge files, keeping order of original sw-versions,
	# then appending other lines from new one in order as well.
	# Could probably do better but it works and files are small..
	awk '!filter[$1] { filter[$1]=1; print }' "$system_versions" \
		| while read -r component oldvers; do
			# drop other_boot / other_boot_linux: no longer used.
			case "$component" in
			other_boot|other_boot_linux) continue;;
			esac

			newvers=$(get_version --install-if "$component" present)
			install_if=${newvers##* }
			newvers=${newvers% *}

			fix_boot_versions
			if [ -z "$newvers" ]; then
				printf "%s\n" "$component $oldvers"
				continue
			fi
			if ! version_update "$install_if" "$oldvers" "$newvers"; then
				info "Skipping install of component $component $newvers (has $oldvers)" >/dev/null
				newvers="$oldvers"
			fi
			printf "%s\n" "$component $newvers"
		done > "$MKSWU_TMP/sw-versions.merged" \
		|| error "Version generation from current versions failed"
	while read -r component newvers install_if newvers_board; do
		case "$newvers_board" in
		""|"*"|"$board") ;;
		*) continue;;
		esac
		oldvers=$(get_version "$component" old)
		[ -n "$oldvers" ] || printf "%s\n" "$component $newvers"
	done < "$MKSWU_TMP/sw-versions.present" >> "$MKSWU_TMP/sw-versions.merged" \
		|| error "Version generation from new versions in swu failed"
}
