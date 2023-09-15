#!/bin/sh

TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPTSDIR="$TMPDIR/scripts"

. "$SCRIPTSDIR/common.sh"

if ! is_locked; then
	# already cleaned up (happens if e.g. pre script failed)
	exit 0
fi

cleanup
rm -rf "$SCRIPTSDIR"
unlock_update
