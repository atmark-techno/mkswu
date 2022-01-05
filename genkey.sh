#!/bin/sh

# SC2039: local is ok for dash and busybox ash
# SC1090: non-constant source directives
# shellcheck disable=SC2039,SC1090

SCRIPT_DIR=$(dirname "$0")
CONFIG="$SCRIPT_DIR"/mkimage.conf
KEYPASS="$PRIVKEY_PASS"
AES=
PLAIN=
CN=
QUIET=
CURVE=secp256k1
DAYS=$((5*365))

if command -v gettext >/dev/null; then
        _gettext() { TEXTDOMAINDIR="$SCRIPT_DIR/locale" TEXTDOMAIN=genkey gettext "$@"; }
else
        _gettext() { printf "%s\n" "$@"; }
fi

error() {
	local fmt="$1"
	shift
	printf "ERROR: $(_gettext "$fmt")\n" "$@" >&2
	exit 1
}

info() {
        local fmt="$1"
        shift
        printf "$(_gettext "$fmt")\n" "$@"
}

usage() {
	info "Usage: %s [options]" "$0"
	info
	info "Options:"
	info "  -c, --config  path"
	info "  --quiet       Do not output info message after key creation"
	info
	info "Signing key options:"
	info "  --plain       generate signing key without encryption"
	info "  --cn          common name for key (mandatory for signing key)"
	info
	info "Encryption key options:"
	info "  --aes         generate aes key instead of default rsa key pair"
}

genkey_aes() {
	local oldumask

	if [ -z "$ENCRYPT_KEYFILE" ]; then
		info "Info: using default aes key path"
		ENCRYPT_KEYFILE="$SCRIPT_DIR/swupdate.aes-key"
		printf "%s\n" '' '# Default encryption key path (set by genkey.sh)' \
			'ENCRYPT_KEYFILE="$SCRIPT_DIR/swupdate.aes-key"' >> "$CONFIG" \
			|| error "Could not update default ENCRYPT_KEYFILE in %s" "$CONFIG"
	fi
	if [ -s "$ENCRYPT_KEYFILE" ]; then
		printf "%s\n" "$ENCRYPT_KEYFILE already exists, skipping"
		return
	fi

	oldumask=$(umask)
	umask 0377
	ENCRYPT_KEY="$(openssl rand -hex 32)" || error "Generating random number failed"
	printf "%s\n" "$ENCRYPT_KEY $(openssl rand -hex 16)" > "$ENCRYPT_KEYFILE"
	umask "$oldumask"

	[ -n "$QUIET" ] && return
	info "Created encryption keyfile %s" "$ENCRYPT_KEYFILE"
	info "You must also enable aes encryption with examples/initial_setup.desc"
	info "or equivalent"

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

	info "Creating signing key %s and its public counterpart %s" "$PRIVKEY" "${PUBKEY##*/}"

	openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:"$CURVE" \
		-keyout "$PRIVKEY" -out "$PUBKEY" -subj "/O=SWUpdate/CN=$CN" \
		${PLAIN:+-nodes} ${PRIVKEY_PASS:+-passout $PRIVKEY_PASS} \
		-days "$DAYS" || error "Generating certificate/key pair failed"

	[ -n "$QUIET" ] && return

	info "%s must be copied over to /etc/swupdate.pem on devices." "$PUBKEY"
	info "The suggested way is using swupdate:"
	info "    ./mkimage.sh examples/initial_setup.desc"
	info "Please set user passwords in initial_setup.desc and generate the image."
	info "If you would like to encrypt your updates, generate your aes key now with:"
	info "    %s --aes" "$0"
}

while [ $# -ge 1 ]; do
	case "$1" in
	"-c"|"--config")
		[ $# -lt 2 ] && error "%s requires an argument" "$1"
		CONFIG="$2"
		[ "${CONFIG#/}" = "$CONFIG" ] && CONFIG=$(realpath "$CONFIG")
		shift 2
		;;
	"--cn")
		[ $# -lt 2 ] && error "%s requires an argument" "$1"
		CN="$2"
		shift 2
		;;
	"--days")
		[ $# -lt 2 ] && error "%s requires an argument" "$1"
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
		|| error "Config %s not found - configure paths there or specify config with --config" "$CONFIG"
fi
. "$CONFIG"
# prefer preserved PRIVKEY_PASS over config value if one was set
[ -n "$KEYPASS" ] && PRIVKEY_PASS="$KEYPASS"

if [ -n "$AES" ]; then
	genkey_aes
else
	genkey_rsa
fi
