link_exists() {
	local base="$1"
	local target="$2"

	if [ "${target:0:1}" = "/" ]; then
		[ -e "/target/$target" ]
	else
		[ -e "/target/$base/$target" ]
	fi
}

update_shadow_user() {
	local user="$1"
	local oldpass

	oldpass=$(awk -F':' '$1 == "'"$user"'" && $3 != "0"' "$SHADOW")
	# password was never set: skip
	[ -n "$oldpass" ] || return
	# password already set on target: also skip
	grep -qE "^$user:[^:]" "$NSHADOW" && return

	if grep -qE "^$user:" "$NSHADOW"; then
		sed -i -e 's:^'"$user"'\:.*:'"${oldpass//:/\\:}"':' "$NSHADOW"
	else
		echo "$oldpass" >> "$NSHADOW"
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
	local PASSWD="${PASSWD:-/etc/passwd}"
	local NPASSWD="${NPASSWD:-/target/etc/passwd}"
	local SHADOW="${SHADOW:-/etc/shadow}"
	local NSHADOW="${NSHADOW:-/target/etc/shadow}"
	local GROUP="${GROUP:-/etc/group}"
	local NGROUP="${NGROUP:-/target/etc/group}"

	# "$PASSWD", group and shadow have to be part of rootfs as
	# rootfs updates can change system users, but we want to keep
	# "real" users as well so copy them over manually:
	# - copy non-existing "real" groups (gid >= 1000)
	# - for each real user (root or uid >= 1000), copy its password
	# if the old one not set and add it to groups it had been added to
	awk -F: '$3 >= 1000 && $3 < 65500 { print $1 }' < "$GROUP" |
		while read -r group; do
			grep -qE "^$group:" "$NGROUP" \
				|| grep -E "^$group:" "$GROUP" >> "$NGROUP"
		done

	awk -F: '$3 == 0 || ( $3 >= 1000 && $3 < 65500 ) { print $1 }' < "$PASSWD" |
		while read -r user; do
			grep -qE "^$user:" "$NPASSWD" \
				|| grep -E "^$user:" "$PASSWD" >> "$NPASSWD"
			update_shadow_user "$user"
			update_user_groups "$user"
		done

	# check there are no user with empty login
	# unless the update explicitely allows it
	grep -q "ALLOW_EMPTY_LOGIN" "$SWDESC" && return
	user=$(awk -F: '$2 == "" { print $1 } ' "$NSHADOW")
	[ -z "$user" ] || error "the following users have an empty password, failing update: $user"

}


SWUPDATE_PEM=/target/etc/swupdate.pem

update_swupdate_certificate()  {
	local certsdir cert pubkey external="" update=""

	# split swupdate.pem into something we can handle, then match
	# with known keys and update as appropriate

	certsdir=$(mktemp -d "$SCRIPTSDIR/certs.XXXXXX") \
		|| error "Could not create temp dir"
	awk '/BEGIN CERTIFICATE/ { idx++; outfile="'"$certsdir"'/cert." idx }
	     outfile { print > outfile }
	     /END CERTIFICATE/ { outfile="" }' "$SWUPDATE_PEM"
	for cert in "$certsdir"/*; do
		pubkey=$(openssl x509 -noout -in "$cert" -pubkey | sed -e '/-----/d' | tr -d '\n')
		case "$pubkey" in
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEYTN7NghmISesYQ1dnby5YkocLAe2/EJ8OTXkx/xGhBVlJ57eGOovtPORd/JMkA6lWI0N/pD5p6eUGcwrQvRtsw==")
			# Armadillo public one-time key, remove it.
			rm -f "$cert"
			update=1
			;;
		"MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEjgbd3SI8+iof3TLL9qTGNlQN84VqkESPZ3TSUkYUgTiEL3Bi1QoYzGWGqfdmrLiNsgJX4QA3gpaC19Q+fWOkEA==")
			# Armadillo internal key, leave it if present.
			;;
		*)
			# Any other key
			external=1
			;;
		esac
	done

	if [ -n "$update" ]; then
		# fail if no user key has been provided
		if [ -z "$external" ]; then
			# just skip this step if flag is set
			grep -q "ALLOW_PUBLIC_CERT" "$SWDESC" \
				|| error "The public one-time swupdate certificate can only be used once. Please add your own certificate. Failing update."
		else
			cat "$certsdir"/* > "$SWUPDATE_PEM" \
				|| error "Could not recreate swupdate.pem certificate"
		fi
	fi

	rm -rf "$certsdir"
}

post_rootfs() {
	local rootfs_created=""
	
	# Sanity check: refuse to continue if someone tries to write a
	# rootfs that was corrupted or "too wrong": check for /bin/sh
	if ! [ -e /target/bin/sh ]; then
		error "No /bin/sh on target: something likely is wrong with rootfs, refusing to continue"
	fi

	if [ -e /target/.created ]; then
		rootfs_created=1
		rm -f /target/.created
	fi

	# if other fs was recreated: fix partition-specific things
	if [ -n "$rootfs_created" ]; then
		# fwenv: either generate a new one for mmc, or copy for sd boot (supersedes version in update)
		if [ "$rootdev" = "/dev/mmcblk2" ]; then
			cat > /target/etc/fw_env.config <<EOF
${rootdev}boot${ab} 0x3fe000 0x2000
${rootdev}boot${ab} 0x3fa000 0x2000
EOF
		else
			cp /etc/fw_env.config /target/etc/fw_env.config
		fi

		# adjust ab_boot
		sed -i -e "s/boot_[01]/boot_${ab}/" /target/etc/fstab

		# use appfs storage for podman if used previously
		if grep -q 'graphroot = "/var/lib/containers/storage' /etc/containers/storage.conf 2>/dev/null; then
			sed -i -e 's@graphroot = .*@graphroot = "/var/lib/containers/storage"@' \
				/target/etc/containers/storage.conf
		fi
	fi

	# extra fiuxps on update
	# in theory we should also check shadow/cert if no update, but the system
	# needs extra os update to start containers so this is enough for safety check
	if update_rootfs; then
		# keep passwords around, and make sure there are no open access user left
		update_shadow

		# remove open access swupdate certificate or complain
		update_swupdate_certificate
	fi

	# and finally set version where appropriate.
	if ! needs_reboot; then
		# updating current version with what is being installed:
		# we should avoid failing from here on.
		update_running_versions "$SCRIPTSDIR/sw-versions.merged"
		soft_fail=1
	else
		cp "$SCRIPTSDIR/sw-versions.merged" "/target/etc/sw-versions"
	fi


	rm -f "$SCRIPTSDIR/sw-versions.merged" "$SCRIPTSDIR/sw-versions.present"
}

[ -n "$TEST_SCRIPTS" ] && return

post_rootfs
