#!/bin/sh

# Allow skipping from env
[ -n "$MKSWU_SKIP_SCRIPTS" ] && exit 0

TMPDIR="${TMPDIR:-/var/tmp}"
MKSWU_TMP="$TMPDIR/scripts"
# SCRIPTSDIR is overridden for scripts embedded with swupdate
SCRIPTSDIR="$MKSWU_TMP"

. "$SCRIPTSDIR/common.sh"

if ! is_locked; then
	# already cleaned up (happens if e.g. pre script failed)
	exit 0
fi

cleanup
rm -rf "$MKSWU_TMP"
unlock_update
