#!/bin/sh

# SC2039: local is ok for dash and busybox ash
# SC1090: non-constant source directives
# shellcheck disable=SC2039,SC1090

SCRIPT_DIR=$(dirname "$0")
CONFIG="$SCRIPT_DIR"/mkimage.conf
AES=
PLAIN=
CN=
QUIET=
CURVE=secp256k1
DAYS=$((5*365))


error() {
	local line
	printf "%s\n" "$@" >&2
	exit 1
}

usage() {
	echo "Usage: $0 [options]"
	echo
	echo "Options:"
	echo "  -c, --config  path"
	echo "  --quiet       Do not output info message after key creation"
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

	if [ -z "$ENCRYPT_KEYFILE" ]; then
		echo "Info: using default aes key path"
		ENCRYPT_KEYFILE="$SCRIPT_DIR/swupdate.aes-key"
		printf "%s\n" '' '# Default encryption key path (set by genkey.sh)' \
			'ENCRYPT_KEYFILE="$SCRIPT_DIR/swupdate.aes-key"' >> "$CONFIG" \
			|| error "Could not update default ENCRYPT_KEYFILE in $CONFIG"
	fi
	if [ -s "$ENCRYPT_KEYFILE" ]; then
		printf "%s\n" "$ENCRYPT_KEYFILE already exists, skipping"
		return
	fi

	oldumask=$(umask)
	umask 0377
	ENCRYPT_KEY="$(openssl rand -hex 32)" || error "No openssl?"
	printf "%s\n" "$ENCRYPT_KEY $(openssl rand -hex 16)" > "$ENCRYPT_KEYFILE"
	umask "$oldumask"

	[ -n "$QUIET" ] && return
	echo "Created encryption keyfile $ENCRYPT_KEYFILE"
	echo "You must also enable aes encryption with examples/initial_setup.desc"
	echo "or equivalent"

}

genkey_rsa() {
	local oldumask
	local PUBKEY="${PRIVKEY%.key}.pem"

	[ -n "$PRIVKEY" ] || error "PRIVKEY is not set in config file"
	if [ -s "$PRIVKEY" ] && [ -s "$PUBKEY" ]; then
		printf "%s\n" "$PRIVKEY already exists, skipping"
		return
	fi
	[ -n "$CN" ] || error "Certificate common name must be provided with --cn <name>"

	echo "Creating signing key $PRIVKEY and its public counterpart ${PUBKEY##*/}"

	openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:"$CURVE" \
		-keyout "$PRIVKEY" -out "$PUBKEY" -subj "/O=SWUpdate/CN=$CN" \
		${PLAIN:+-nodes} ${PRIVKEY_PASS:+-passout $PRIVKEY_PASS} \
		-days "$DAYS"

	[ -n "$QUIET" ] && return

	echo "$PUBKEY must be copied over to /etc/swupdate.pem on boards."
	echo "The suggested way is using swupdate:"
	echo "    ./mkimage.sh examples/initial_setup.desc"
	echo "Please set user passwords in initial_setup.desc and generate the image."
	echo "If you would like to encrypt your updates, generate your aes key now with:"
	echo "    $0 --aes"
}

while [ $# -ge 1 ]; do
	case "$1" in
	"-c"|"--config")
		[ $# -lt 2 ] && error "$1 requires an argument"
		CONFIG="$2"
		[ "${CONFIG#/}" = "$CONFIG" ] && CONFIG=$(realpath "$CONFIG")
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
	"--quiet")
		QUIET=1
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

if ! [ -r "$CONFIG" ]; then
	# generate defaults if absent
	[ "${CONFIG##*/}" = "mkimage.conf" ] \
		&& "$SCRIPT_DIR/mkimage.sh" --mkconf
	[ -r "$CONFIG" ] \
		|| error "Config $CONFIG not found - configure paths there or specify config with --config"
fi
. "$CONFIG"

if [ -n "$AES" ]; then
	genkey_aes
else
	genkey_rsa
fi
