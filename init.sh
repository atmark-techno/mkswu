#!/bin/bash

SCRIPT_DIR="$(dirname "$0")"
CONFIG="$SCRIPT_DIR/mkimage.conf"
TEXTDOMAINDIR="$SCRIPT_DIR/locale"
TEXTDOMAIN=init

error() {
	printf "ERROR: %s\n" "$@" >&2
	exit 1
}
info() {
	printf "%s\n" "$@" >&2
}

genkey() {
	local CN

	[[ -e "$PUBKEY" ]] && [[ -e "$PRIVKEY" ]] && return

	while [[ -z "$CN" ]]; do
		read -r -p $"Enter certificate common name: " CN
	done

	"$SCRIPT_DIR/genkey.sh" --quiet --cn "$CN" \
		|| error $"Could not generate swupdate certificate"

	# Also prompt for encryption
	local AES=inval

	[[ -n "$ENCRYPT_KEYFILE" ]] && [[ -e "$ENCRYPT_KEYFILE" ]] && return

	while ! [[ "$AES" =~ ^([Yy]|[Yy][Ee][Ss]|[Nn]|[Nn][Oo]|)$ ]]; do
		read -r -p $"Use AES encryption? (N/y) " AES
	done
	case "$AES" in
	[Yy]|[Yy][Ee][Ss])
		"$SCRIPT_DIR/genkey.sh" --quiet --aes \
			|| error $"Could not generate AES key"
		;;
	esac
}

geninitdesc() {
	local KEEPATMARKPEM=inval
	local ROOTPW
	local ROOTPW_CONFIRM
	local ATMARKPW
	local ATMARKPW_CONFIRM
	local desc="$SCRIPT_DIR/initial_setup.desc"

	[[ -e "$desc" ]] && return

	while ! [[ "$KEEPATMARKPEM" =~ ^([Yy]|[Yy][Ee][Ss]|[Nn]|[Nn][Oo]|)$ ]]; do
		read -r -p $"Allow updates signed by Atmark Techno? (Y/n) " KEEPATMARKPEM
	done
	while true; do
		read -s -r -p $"root password: " ROOTPW
		echo
		if [[ -z "$ROOTPW" ]]; then
			info $"A root password is required"
			continue
		fi
		read -s -r -p $"root password (confirm): " ROOTPW_CONFIRM
		echo
		if [[ "$ROOTPW" != "$ROOTPW_CONFIRM" ]]; then
			info $"Passwords do not match"
			continue
		fi
		ROOTPW=$(printf 'import crypt; print(crypt.crypt(r"%s", crypt.METHOD_SHA512))' "${ROOTPW//\"/\"\'\"\'r\"}" | python3)
		[[ -n "$ROOTPW" ]] || error $"Could not hash password"
		break
	done

	while true; do
		read -s -r -p $"atmark user password (empty = same as root): " ATMARKPW
		echo
		read -s -r -p $"atmark user password (confirm): " ATMARKPW_CONFIRM
		echo
		if [[ "$ATMARKPW" != "$ATMARKPW_CONFIRM" ]]; then
			info $"Passwords do not match"
			continue
		fi
		if [[ -z "$ATMARKPW" ]]; then
			ATMARKPW="$ROOTPW_CONFIRM"
		fi
		ATMARKPW=$(printf 'import crypt; print(crypt.crypt(r"%s", crypt.METHOD_SHA512))' "${ATMARKPW//\"/\"\'\"\'r\"}" | python3)
		[[ -n "$ATMARKPW" ]] || error $"Could not hash password"
		break
	done


	# cleanup if we fail here
	trap "rm -f ${desc@Q}" EXIT

	cp "$SCRIPT_DIR/examples/initial_setup.desc" "$desc" \
		|| error $"Could not copy initial_setup.desc from example dir"
	case "$KEEPATMARKPEM" in
	[Nn]|[Nn][Oo])
		sed -i -e 's@>> /etc/swupdate.pem@> /etc/swupdate.pem@' "$desc" \
			|| error $"Could not update $desc"
	esac
	sed -i -e 's:\(^[ \t]*"usermod\).*atmark:\1 -p '\'\""'$ATMARKPW'"\"\'' atmark:' \
			-e 's:\(^[ \t]*"usermod\).*root:\1 -p '\'\""'$ROOTPW'"\"\'' root:' "$desc" \
		|| error $"Could not update $desc"

	trap "" EXIT
}

mkimageinitswu() {
	"$SCRIPT_DIR/mkimage.sh" "$SCRIPT_DIR/initial_setup.desc" || error $"Could not generate initial setup swu"
	echo
	info $"You can use \"$SCRIPT_DIR/initial_setup.swu\" as is or regenerate an image"
	info $"with extra modules with \"$SCRIPT_DIR/mkimage.sh\" \"$SCRIPT_DIR/initial_setup.desc\" other_desc_files"
}


if ! [[ -r "$CONFIG" ]]; then
        # generate defaults if absent
        [[ "${CONFIG##*/}" = "mkimage.conf" ]] \
                && "$SCRIPT_DIR/mkimage.sh" --mkconf
        [[ -r "$CONFIG" ]] \
                || error $"Config $CONFIG not found - configure paths there or specify config with --config"
fi
. "$CONFIG"

genkey
geninitdesc
mkimageinitswu


