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
	local KEYPASS KEYPASS_CONFIRM

	[[ -e "$PUBKEY" ]] && [[ -e "$PRIVKEY" ]] && return

	while [[ -z "$CN" ]]; do
		read -r -p $"Enter certificate common name: " CN
	done

	while true; do
		read -s -r -p $"Enter private key password (4-1024 char) " KEYPASS
		echo
		if [[ -z "$KEYPASS" ]]; then
			info $"Empty key password is not recommended, re-enter empty to confirm"
		elif [[ "${#KEYPASS}" -lt 4 ]] || [[ "${#KEYPASS}" -gt 1024 ]]; then
			info $"Must be between 4 and 1024 characters long"
			continue
		fi
		read -s -r -p $"private key password (confirm): " KEYPASS_CONFIRM
		echo
		if [[ "$KEYPASS" != "$KEYPASS_CONFIRM" ]]; then
			info $"Passwords do not match"
			continue
		fi
		break
	done

	if [[ -n "$KEYPASS" ]]; then
		echo "$KEYPASS" | PRIVKEY_PASS="stdin" \
			"$SCRIPT_DIR/genkey.sh" --quiet --cn "$CN"
	else
		"$SCRIPT_DIR/genkey.sh" --plain --quiet --cn "$CN"
	fi || exit 1

	# Also prompt for encryption
	local AES=inval

	[[ -n "$ENCRYPT_KEYFILE" ]] && [[ -e "$ENCRYPT_KEYFILE" ]] && return

	while ! [[ "$AES" =~ ^([Yy]|[Yy][Ee][Ss]|[Nn]|[Nn][Oo]|)$ ]]; do
		read -r -p $"Use AES encryption? (N/y) " AES
	done
	case "$AES" in
	[Yy]|[Yy][Ee][Ss])
		"$SCRIPT_DIR/genkey.sh" --quiet --aes \
			|| exit 1
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
	info ""
	info $"Note that once installed, you must preserve this directory as losing"
	info $"key files means you will no longer be able to install new updates without"
	info $"manually adjusting /etc/swupdate.pem on devices"
}


if ! [[ -r "$CONFIG" ]]; then
        # generate defaults if absent
        [[ "${CONFIG##*/}" = "mkimage.conf" ]] \
                && "$SCRIPT_DIR/mkimage.sh" --mkconf
        [[ -r "$CONFIG" ]] \
                || error $"Config $CONFIG not found"
fi
. "$CONFIG"

genkey
geninitdesc
mkimageinitswu


