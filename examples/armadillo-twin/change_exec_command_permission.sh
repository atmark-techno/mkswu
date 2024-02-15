#!/bin/sh

CONF_FILE="/etc/atmark/armadillo-twin/agent.conf"
CONF_EXAMPLE="/etc/atmark/armadillo-twin/agent.conf.example"

error() {
	printf "%s\n" "$@" >&2
	exit 1
}

main () {
	local yn="$1"
	[ "$yn" = "yes" ] || [ "$yn" = "no" ] || error "requires 'yes' or 'no' argument."

	local src="$CONF_FILE"
	if ! [ -e "$CONF_FILE" ]; then
		[ -e "$CONF_EXAMPLE" ] \
			|| error "$CONF_EXAMPLE was not found, please install armadillo-twin-agent first."
		src="$CONF_EXAMPLE"
	fi

	# delete any "allow-exec-command" lines and append at the end
	awk -v "yn=$yn" '! /^\s*allow-exec-command\s*=/ {
				print
			}
			END {
				print "allow-exec-command = " yn
			}' "$src" > "$CONF_FILE.tmp" \
		&& mv "$CONF_FILE.tmp" "$CONF_FILE" \
		|| error "Could not update $CONF_FILE"
}

main "$@"
