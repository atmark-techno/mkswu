#!/bin/sh

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
CONFIG=./mkimage.conf
AES=
PLAIN=
CN=
CURVE=secp256k1


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
	echo "  -c, --config  path"
	echo
	echo "Signing key options:"
	echo "  --plain       generate signing key without encryption"
	echo "  --cn          common name for key (mandatory for signing key)"
	echo
	echo "Encryption key options:"
	echo "  --aes         generate aes key instead of default rsa key pair"
}

genkey_aes() {
	local oldumask

	[ -n "$ENCRYPT_KEYFILE" ] \
		|| error "Must set ENCRYPT_KEYFILE in config file (or pass --config if required)"
	if [ -s "$ENCRYPT_KEYFILE" ]; then
		echo "$ENCRYPT_KEYFILE already exists, skipping"
		return
	fi

	echo "Creating encryption keyfile $ENCRYPT_KEYFILE"
	echo "That file must be copied as /etc/swupdate.aes-key as 0400 on boards"

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
	if [ -s "$PRIVKEY" ]; then
		echo "$PRIVKEY already exists, skipping"
		return
	fi
	[ -n "$CN" ] || error "Certificate common name must be provided with --cn <name>"

	echo "Creating signing key $PRIVKEY and its public counterpart ${PUBKEY##*/}"

	openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:"$CURVE" \
		-keyout "$PRIVKEY" -out "$PUBKEY" -subj "/O=SWUpdate/CN=$CN" \
		${PLAIN:+-nodes} ${PRIVKEY_PASS:+-passout $PRIVKEY_PASS}

	echo "$PUBKEY must be copied over to /etc/swupdate.pem on boards"
	echo "Please append it to the existing key if you plan on using vendor updates,"
	echo "or replace the file to allow only your own."
}

while [ $# -ge 1 ]; do
	case "$1" in
	"-c"|"--config")
		[ $# -lt 2 ] && error "$1 requires an argument"
		CONFIG="$2"
		[ "${CONFIG#/}" = "$CONFIG" ] && CONFIG="./$CONFIG"
		shift 2
		;;
	"--cn")
		[ $# -lt 2 ] && error "$1 requires an argument"
		CN=$1
		shift 2
		;;
	"--plain")
		PLAIN=1
		shift
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

[ -r "$CONFIG" ] || error "Config $CONFIG not found - configure paths there or specify config with --config"
. "$CONFIG"

if [ -n "$AES" ]; then
	genkey_aes
else
	genkey_rsa
fi
