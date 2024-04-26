# SPDX-License-Identifier: MIT

update_shadow_user() {
	local user="$1"
	local oldpass

	oldpass=$(awk -F':' '$1 == "'"$user"'" && $3 != "0"' "$SHADOW" \
			| sed -e 's/[\\:&]/\\&/g')
	# password was never set: skip
	[ -n "$oldpass" ] || return
	# password already set on target: also skip
	grep -qE "^$user:[^!:]" "$NSHADOW" && return

	if grep -qE "^$user:" "$NSHADOW"; then
		sed -i -e 's:^'"$user"'\:.*:'"$oldpass"':' "$NSHADOW"
	else
		echo "$oldpass" | sed -e 's/\\\([\\:&]\)/\1/g' >> "$NSHADOW"
	fi || error "Could not update shadow for $user"
}

update_user_groups() {
	local user="$1"
	local group

	awk -F: '$4 ~ /(,|^)'"$user"'(,|$)/ { print $1 }' < "$GROUP" |
		while read -r group; do
			# already set
			grep -qE "^$group:.*[:,]$user(,|$)" "$NGROUP" \
				&& continue

			if grep -qE "^$group:.*:$" "$NGROUP"; then
				sed -i -e 's/^'"$group"':.*:/&'"$user"'/' "$NGROUP"
			else
				sed -i -e 's/^'"$group"':.*/&,'"$user"'/' "$NGROUP"
			fi || error "Could not update group $group / $user"
		done
}

update_shadow() {
	local user group
	# test constants
	local PASSWD="${PASSWD:-$fsroot/etc/passwd}"
	local NPASSWD="${NPASSWD:-/target/etc/passwd}"
	local SHADOW="${SHADOW:-$fsroot/etc/shadow}"
	local NSHADOW="${NSHADOW:-/target/etc/shadow}"
	local GROUP="${GROUP:-$fsroot/etc/group}"
	local NGROUP="${NGROUP:-/target/etc/group}"

	# "$PASSWD", group and shadow have to be part of rootfs as
	# rootfs updates can change system users, but we want to keep
	# "real" users as well so copy them over manually:
	# - copy non-existing "real" groups (gid >= 1000)
	# - for each real user (root, abos* or uid >= 1000), copy its password
	# if the old one not set and add it to groups it had been added to
	awk -F: '$3 >= 1000 && $3 < 65500 { print $1 }' < "$GROUP" |
		while read -r group; do
			grep -qE "^$group:" "$NGROUP" \
				|| grep -E "^$group:" "$GROUP" >> "$NGROUP"
		done

	awk -F: '$1 == "root" || $1 ~ /^abos/ \
			|| ( $3 >= 1000 && $3 < 65500 ) {
				print $1
			}' < "$PASSWD" |
		while read -r user; do
			grep -qE "^$user:" "$NPASSWD" \
				|| grep -E "^$user:" "$PASSWD" >> "$NPASSWD"
			update_shadow_user "$user"
			update_user_groups "$user"
		done

	# check there are no user with empty login
	# unless the update explicitely allows it
	[ -n "$(mkswu_var ALLOW_EMPTY_LOGIN)" ] && return
	user=$(awk -F: '$2 == "" { print $1 } ' "$NSHADOW")
	[ -z "$user" ] || error "the following users have an empty password, failing update: $user"

}


update_swupdate_certificate()  {
	local certsdir cert pubkey
	local public_onetime_path=""
	local atmark_present="" atmark_seen=""
	local user_present="" user_seen=""
	# test constants
	local SWUPDATE_PEM=${SWUPDATE_PEM:-/target/etc/swupdate.pem}
	# Use tmpdir from SWU version of the scripts as embedded tmp
	# never contains certificates
	local MKSWU_SWU_TMP="$TMPDIR/scripts"

	# what certificates were embedded into swu, if any?
	for cert in "$MKSWU_SWU_TMP/certs_atmark/"*; do
		[ -e "$cert" ] && atmark_present=1
		break
	done
	for cert in "$MKSWU_SWU_TMP/certs_user/"*; do
		[ -e "$cert" ] && user_present=1
		break
	done

	# split swupdate.pem into something we can handle, then match
	# with known certificates and update as appropriate

	certsdir=$(mktemp -d "$MKSWU_TMP/certs.XXXXXX") \
		|| error "Could not create temp dir"
	awk '! outfile { idx++; outfile="'"$certsdir"'/cert." idx }
	     outfile { print > outfile }
	     /END CERTIFICATE/ { outfile="" }' "$SWUPDATE_PEM"
	for cert in "$certsdir"/cert.*; do
		[ -e "$cert" ] || continue
		pubkey=$(openssl x509 -noout -in "$cert" -pubkey | sed -e '/-----/d' | tr -d '\n')
		case "$pubkey" in
		# Armadillo public one-time cert
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEYTN7NghmISesYQ1dnby5YkocLAe2/EJ8OTXkx/xGhBVlJ57eGOovtPORd/JMkA6lWI0N/pD5p6eUGcwrQvRtsw==")
			# remove duplicates if it was already set
			[ -n "$public_onetime_path" ] && rm -f "$public_onetime_path"
			# we don't remove it immediately because we allow updates from atmark
			# updates to leave it
			public_onetime_path="$cert"
			;;
		# certificate for atmark are handled separately
		# atmark-1|atmark-2
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEjgbd3SI8+iof3TLL9qTGNlQN84VqkESPZ3TSUkYUgTiEL3Bi1QoYzGWGqfdmrLiNsgJX4QA3gpaC19Q+fWOkEA=="| \
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAERkRP5eTXBTG760gEmBfCBz4fWyYfUx3a+sYyHe4uc1sQN2bavxfaBlJmyGI4MY/Pkjh5FDVcddZfil552WUoWQ==")
			# atmark certificates: delete if we have new ones, or just keep.
			[ -n "$atmark_present" ] && rm -f "$cert"
			atmark_seen=1
			;;
		*)
			# user certificates: delete if we have new ones,
			# otherwise keep whatever we have here.
			[ -n "$user_present" ] && rm -f "$cert"
			user_seen=1
			;;
		esac
	done

	if [ -n "$public_onetime_path" ]; then
		if [ -z "$user_seen$user_present" ]; then
			# don't remove one-time cert if no external cert provided
			# fail unless explicitely allowed
			[ -n "$(mkswu_var ALLOW_PUBLIC_CERT)" ] \
				|| error "The public one-time swupdate certificate can only be used once. Please add your own certificate. Failing update."
		else
			rm -f "$public_onetime_path"
		fi
	fi
	(
		# ignore errors, might not be any cert left here
		cat "$certsdir"/cert.* 2>/dev/null
		if [ -n "$atmark_seen" ]; then
			# only add atmark certs if they're currently installed
			for cert in "$MKSWU_SWU_TMP/certs_atmark/"*; do
				[ -e "$cert" ] || continue
				cat "$cert" || exit 1
			done
		fi
		for cert in "$MKSWU_SWU_TMP/certs_user/"*; do
			[ -e "$cert" ] || continue
			# add comment to older certificates
			grep -qE '^# ' "$cert" || echo "# ${cert##*/}"
			cat "$cert" || exit 1
		done
	) > "$SWUPDATE_PEM" \
		|| error "Could not recreate swupdate.pem certificates"

	rm -rf "$certsdir"
}
