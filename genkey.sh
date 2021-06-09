#!/bin/sh

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
CONFIG=./mkimage.conf
AES=
RSA_CIPHER=-aes-256-cbc

error() {
	local line
	for line; do
		echo "$line" >&2
	done
	exit 1
}

usage() {
	echo "Usage: $0 [options]"
	echo
	echo "Options:"
	echo "  -c, --config         path"
	echo "  --aes                generate aes key instead of default rsa key pair"
	echo "  --rsa-cipher cipher  cipher to use for rsa key encryption"
	echo "                       (default -aes-256-cbc, set empty for clear text)"
}

genkey_aes() {
	local oldumask

	[ -n "$ENCRYPT_KEYFILE" ] \
		|| error "Must set ENCRYPT_KEYFILE in config file (or pass --config if required)"
	[ -s "$ENCRYPT_KEYFILE" ] \
		&& error "$ENCRYPT_KEYFILE already exists, aborting"

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
	[ -s "$PRIVKEY" ] && error "$PRIVKEY already exists, skipping"

	echo "Creating signing key $PRIVKEY and its public counterpart ${PUBKEY##*/}"
	echo "$PUBKEY must be copied over to /etc/swupdate.pem on boards"

	oldumask=$(umask)
	umask 0077
	openssl genpkey -out "$PRIVKEY" -algorithm rsa-pss \
		-pkeyopt rsa_keygen_bits:4096 $RSA_CIPHER \
		${PRIVKEY_PASS:+-pass $PRIVKEY_PASS}
	umask "$oldumask"
	openssl rsa -in "$PRIVKEY" -out "$PUBKEY" -outform PEM \
		${PRIVKEY_PASS:+-passin $PRIVKEY_PASS} \
		-pubout

}

while [ $# -ge 1 ]; do
	case "$1" in
	"-c"|"--config")
		[ $# -lt 2 ] && error "$1 requires an argument"
		CONFIG="$2"
		[ "${CONFIG#/}" = "$CONFIG" ] && CONFIG="./$CONFIG"
		shift 2
		;;
	"--rsa-cipher")
		[ $# -lt 2 ] && error "$1 requires an argument"
		RSA_CIPHER="$2"
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
