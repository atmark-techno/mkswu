#!/bin/sh

# Script configuration: edit this if required!
# user given here must have CREATE_TARGET,READ_TARGET_SECURITY_TOKEN permissions
HAWKBIT_USER=device
HAWKBIT_PASSWORD=
HAWKBIT_URL=
HAWKBIT_TENANT=default
# set custom options for suricatta block or in general in the config
CUSTOM_SWUPDATE_SURICATTA_CFG="" # e.g. "polldelay = 86400;"
CUSTOM_SWUPDATE_CFG=""
# set to non-empty if server certificate is invalid
SSL_NO_CHECK_CERT=
# or set to cafile that must have been updated first
SSL_CAFILE=
# ... or paste here base64 encoded crt content, e.g.
# SSL_CA_CONTENT="
# -----BEGIN CERTIFICATE-----
# MIIBejCCASGgAwIBAgIUb5eWXmv2Cwvbf0IoW6PDUBF3HmkwCgYIKoZIzj0EAwIw
# ...
# Af8EBTADAQH/MAoGCCqGSM49BAMCA0cAMEQCIAlxsxPaRVriLlxLHWk9eYXgqtws
# NGdeI3cn+cafbzdrAiAQoDboWCq1tyAjJqJ4vFyOUcdBD8nY+GESXCIFQNaEWw==
# -----END CERTIFICATE-----
# "
SSL_CA_CONTENT="
"
# ... or add your own options if required
CURLOPT=-s

error() {
	printf "%s\n" "$@" >&2
	exit 1
}

wait_network() {
	local HAWKBIT_HOST=${HAWKBIT_URL#http*://}
	HAWKBIT_HOST=${HAWKBIT_HOST%%/*}
	local PORT=80
	case "$HAWKBIT_URL" in
	https://*) PORT=443;;
	esac
	case "$HAWKBIT_HOST" in
	*:*) PORT=${HAWKBIT_HOST##*:}; HAWKBIT_HOST=${HAWKBIT_HOST%:*};;
	esac

	# wait up to 30 seconds for network
	timeout 30s sh -c "
		while ! nc -w 5 $HAWKBIT_HOST $PORT </dev/null >/dev/null 2>&1; do
			sleep 1;
		done"
}

init() {
	[ -n "$HAWKBIT_PASSWORD" ] && [ -n "$HAWKBIT_URL" ] || error "Variables top of script must be set"
	HAWKBIT_LOGIN="$HAWKBIT_USER:$HAWKBIT_PASSWORD"

	DEVICE_ID=$(device-info -s) || error "Please install device-info"

	[ -n "$SSL_NO_CHECK_CERT" ] && CURLOPT="$CURLOPT -k"
	if [ -n "$SSL_CAFILE" ]; then
		CURLOPT="$CURLOPT --cacert $SSL_CAFILE"
	else
		# set default for swupdate
		SSL_CAFILE="/etc/ssl/certs/ca-certificates.crt"
	fi
	# write CA and update cert if not empty
	if echo "$SSL_CA_CONTENT" | grep -q '[[:alnum:]]'; then
		echo "$SSL_CA_CONTENT" \
			| sed -e '/^[ \t]*$/d' > /usr/local/share/ca-certificates/hawkbit.crt \
			|| error "Could not write certificate"
		cat /usr/local/share/ca-certificates/hawkbit.crt \
			>> /etc/ssl/certs/ca-certificates.crt \
			|| error "Could not update ca-certificates.crt"
	fi

	wait_network

	command -v curl > /dev/null \
		|| apk add curl \
		|| error "curl not found and could not be installed"
}

# register a device name for us
register_device() {
	CONTROLLER_ID="armadillo-$DEVICE_ID${REGISTER_RETRY:+-$REGISTER_RETRY}"
	curl $CURLOPT -u "$HAWKBIT_LOGIN" -X POST "${HAWKBIT_URL}/rest/v1/targets" \
		-H 'Content-Type: application/json' -d '[{
			"controllerId": "'"$CONTROLLER_ID"'",
			"name": "Armadillo '"$DEVICE_ID${REGISTER_RETRY:+ ($REGISTER_RETRY)}"'"
		}]' -o curlout \
		|| error "Could not send request to $HAWKBIT_URL"
# known to return one of the following:
# [{"createdBy":"device","createdAt":1634611542824,"lastModifiedBy":"device","lastModifiedAt":1634611542824,"name":"Device 01","description":"One device","controllerId":"device01","updateStatus":"unknown","securityToken":"005cec0b77d38f4081cf3682c9439e0b","requestAttributes":true,"_links":{"self":{"href":"https://my.hawkbit.server/rest/v1/targets/device01"}}}]
# {"exceptionClass":"org.eclipse.hawkbit.repository.exception.EntityAlreadyExistsException","errorCode":"hawkbit.server.error.repo.entitiyAlreayExists","message":"The given entity already exists in database"}
# {"timestamp":"2021-10-19T02:45:20.688+0000","status":401,"error":"Unauthorized","message":"Unauthorized","path":"/rest/v1/targets"}

	# note: we should really use something like jq for this,
	# but it's a whole 1MB of dependencies just to get this token...
	SECURITY_TOKEN=$(sed -ne 's/.*securityToken[^0-9a-f]*\([0-9a-f]*\).*/\1/p' < curlout)
	[ -n "$SECURITY_TOKEN" ] && return

	grep -q "Unauthorized" curlout \
		&& error "defined user $HAWKBIT_USER is not valid (bad password?) or does not have CREATE_TARGET permission"
	grep -q "createdBy" curlout \
		&& error "defined user $HAWKBIT_USER does not have READ_TARGET_SECURITY_TOKEN permission"
	grep -q "AlreadyExists" curlout \
		|| error "Unknown error while attempting to register: $(cat curlout)"

	# try again with another name
	REGISTER_RETRY=$((REGISTER_RETRY+1))
	register_device
}

update_swupdate_cfg() {
	# nuke the suricatta section if present, then append our own
	sed '/suricatta:/,/}/d' < /etc/swupdate.cfg > swupdate.cfg \
		|| error "Could not update swupdate.cfg"
	cat >> swupdate.cfg <<EOF \
		|| error "Could not update swupdate.cfg"
suricatta: {
  url = "${HAWKBIT_URL%/}";
  tenant = "$HAWKBIT_TENANT";
  id = "$CONTROLLER_ID";
  targettoken = "$SECURITY_TOKEN";
  cafile = "$SSL_CAFILE";
EOF
	if [ -n "$SSL_NO_CHECK_CERT" ]; then
		echo "  nocheckcert = true;" >> swupdate.cfg \
			|| error "Could not update swupdate.cfg"
	fi
	if [ -n "$CUSTOM_SWUPDATE_SURICATTA_CFG" ]; then
		printf "%s\n" "$CUSTOM_SWUPDATE_SURICATTA_CFG" >> swupdate.cfg \
			|| error "Could not update swupdate.cfg"
	fi
	echo "}" >> swupdate.cfg \
		|| error "Could not update swupdate.cfg"
	if [ -n "$CUSTOM_SWUPDATE_CFG" ]; then
		echo >> swupdate.cfg \
			|| error "Could not update swupdate.cfg"
		printf "%s\n" "$CUSTOM_SWUPDATE_CFG" >> swupdate.cfg \
			|| error "Could not update swupdate.cfg"
	fi
	mv swupdate.cfg /etc/swupdate.cfg \
		|| error "Could not update swupdate.cfg"

	# enable the service
	rc-update add swupdate-hawkbit default \
		|| error "Could not update swupdate.cfg"
}

main() {
	local DEVICE_ID SECURITY_TOKEN REGISTER_RETRY
	local HAWKBIT_LOGIN CONTROLLER_ID
	local temp

	temp=$(mktemp -d /tmp/register_hawkbit.XXXXXX) \
		|| error "Could not create temporary directory"
	trap "rm -rf '$temp'" EXIT

	cd "$temp" || error "Could not enter temp dir"

	init
	wait_network
	register_device
	update_swupdate_cfg
}

main
