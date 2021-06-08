#!/bin/sh

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
CONFIG=./mkimage.conf
AES=

error() {
	local line
	for line; do
		echo "$line" >&2
	done
	exit 1
}

genkey_aes() {
	local oldumask

	[ -n "$ENCRYPT_KEYFILE" ] || error "Must set ENCRYPT_KEYFILE in config file (or pass --config if required)"
	[ -e "$ENCRYPT_KEYFILE" ] && error "$ENCRYPT_KEYFILE already exists, aborting"

	echo "Creating encryption keyfile $ENCRYPT_KEYFILE"
	echo "That file must be copied over to /etc/swupdate.aes-key as 0400 on boards"
	oldumask=$(umask)
	umask 0077
	ENCRYPT_KEY="$(openssl rand -hex 32)" || error "No openssl?"
	echo "$ENCRYPT_KEY $(openssl rand -hex 16)" > "$ENCRYPT_KEYFILE"
	umask "$oldumask"
}

genkey_rsa() {
	local oldumask
	local PUBKEY="${PRIVKEY%.key}.pem"

	[ -n "$PRIVKEY" ] || error "PRIVKEY is not set in config file"
	[ -e "$PRIVKEY" ] && error "$PRIVKEY already exists, skipping"

	echo "Creating signing key $PRIVKEY and its public counterpart ${PUBKEY##*/}"
	echo "$PUBKEY must be copied over to /etc/swupdate.pem on boards"

	oldumask=$(umask)
	umask 0077
	openssl genrsa -aes256 -out "$PRIVKEY"
	umask "$oldumask"
	openssl rsa -in "$PRIVKEY" -out "$PUBKEY" -outform PEM -pubout
}

while [ $# -ge 1 ]; do
	case "$1" in
	"-c"|"--config")
		[ $# -lt 2 ] && error "$1 requires an argument"
		CONFIG="$2"
		[ "${CONFIG#/}" = "$CONFIG" ] && CONFIG="./$CONFIG"
		shift 2
		;;
	"--aes")
		AES=1
		shift
		;;
	"-h"|"--help"|"-"*)
		usage
		exit 0
		;;
	*)
		break
		;;
	esac
done

. "$CONFIG"

if [ -n "$AES" ]; then
	genkey_aes
else
	genkey_rsa
fi
