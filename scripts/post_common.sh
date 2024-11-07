# SPDX-License-Identifier: MIT

check_shadow_empty_password() {
	local user
	local NSHADOW="${NSHADOW:-/target/etc/shadow}"

	# check there are no user with empty login
	# unless the update explicitely allows it
	[ -n "$(mkswu_var ALLOW_EMPTY_LOGIN)" ] && return
	user=$(awk -F: '$2 == "" && $3 != "0" { print $1 }' "$NSHADOW")
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
	awk -v certsdir="$certsdir" '
		! outfile { idx++; outfile=certsdir "/cert." idx }
		outfile { print > outfile }
		/END CERTIFICATE/ { outfile="" }' "$SWUPDATE_PEM"
	for cert in "$certsdir"/cert.*; do
		[ -e "$cert" ] || continue
		pubkey=$(openssl x509 -noout -in "$cert" -pubkey | sed -e '/-----/d' | tr -d '\n')
		case "$pubkey" in
		# Armadillo public one-time cert
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEYTN7NghmISesYQ1dnby5YkocLAe2/EJ8OTXkx/xGhBVlJ57eGOovtPORd/JMkA6lWI0N/pD5p6eUGcwrQvRtsw==")
			# remove duplicates if it was already set
			if [ -n "$public_onetime_path" ]; then
				rm -f "$public_onetime_path" \
					|| error "Could not remove temporary file"
			fi
			# we don't remove it immediately because we allow updates from atmark
			# updates to leave it
			public_onetime_path="$cert"
			;;
		# certificate for atmark are handled separately
		# atmark-1|atmark-2|atmark-3
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEjgbd3SI8+iof3TLL9qTGNlQN84VqkESPZ3TSUkYUgTiEL3Bi1QoYzGWGqfdmrLiNsgJX4QA3gpaC19Q+fWOkEA=="| \
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAERkRP5eTXBTG760gEmBfCBz4fWyYfUx3a+sYyHe4uc1sQN2bavxfaBlJmyGI4MY/Pkjh5FDVcddZfil552WUoWQ=="| \
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAE6IZHb+5RM8wxXWB8NdVpy5k7THY61SKP7+4GqegW2SDJ3yYUYuwL7MZVjKtauUYUYQVvKzEc+ghxOdQgModzfA==")
			# atmark certificates: delete if we have new ones, or just keep.
			if [ -n "$atmark_present" ]; then
				rm -f "$cert" \
					|| error "Could not remove temporary file"
			fi
			atmark_seen=1
			;;
		*)
			# user certificates: delete if we have new ones,
			# otherwise keep whatever we have here.
			if [ -n "$user_present" ]; then
				rm -f "$cert" \
					|| error "Could not remove temporary file"
			fi
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
			info "No user certificate present: keeping one-time public certificate"
		else
			rm -f "$public_onetime_path" \
				|| error "Could not remove temporary file"
			info "Removing one-time public certificate"
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
