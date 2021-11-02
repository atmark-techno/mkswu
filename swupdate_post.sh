#!/bin/sh

TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPTSDIR="$TMPDIR/scripts"

. "$SCRIPTSDIR/common.sh"
. "$SCRIPTSDIR/versions.sh"

. "$SCRIPTSDIR/post_init.sh"
. "$SCRIPTSDIR/post_appfs.sh"
. "$SCRIPTSDIR/post_rootfs.sh"
. "$SCRIPTSDIR/post_uboot.sh"
. "$SCRIPTSDIR/post_success.sh"

cleanup
rm -rf "$SCRIPTSDIR"

if grep -q POSTACT_POWEROFF "$SWDESC" 2>/dev/null; then
	echo "swupdate triggering poweroff!" >&2
	poweroff
elif grep -q POSTACT_WAIT "$SWDESC" 2>/dev/null; then
	echo "swupdate waiting until external reboot" >&2
	sleep infinity
elif needs_reboot; then
	echo "swupdate triggering reboot!" >&2
	reboot
elif [ -n "$SWUPDATE_HAWKBIT" ]; then
	echo "Restarting swupdate-hawkbit service" >&2
	rc-service swupdate-hawkbit restart
fi
