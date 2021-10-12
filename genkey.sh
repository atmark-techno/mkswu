#!/bin/sh

# SC2039: local is ok for dash and busybox ash
# SC1090: non-constant source directives
# shellcheck disable=SC2039,SC1090

CONFIG=./mkimage.conf
AES=
PLAIN=
CN=
CURVE=secp256k1
DAYS=$((5*365))


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
	echo "You must also enable aes encryption with initial_setup.desc or equivalent"

	oldumask=$(umask)
	umask 0377
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
		${PLAIN:+-nodes} ${PRIVKEY_PASS:+-passout $PRIVKEY_PASS} \
		-days "$DAYS"

	echo "$PUBKEY must be copied over to /etc/swupdate.pem on boards."
	echo "The suggested way is using swupdate:"
	echo "    ./mkimage.sh initial_setup.desc -o initial_setup.swu"
	echo "Please set user passwords in initial_setup.desc and generate the image."
	echo "If you would like to encrypt your updates, generate your aes key now with:"
	echo "    $0 --aes"
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
		CN="$2"
		shift 2
		;;
	"--days")
		[ $# -lt 2 ] && error "$1 requires an argument"
		DAYS="$2"
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
