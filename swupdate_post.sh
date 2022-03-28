#!/bin/sh

TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPTSDIR="$TMPDIR/scripts"

. "$SCRIPTSDIR/common.sh"

. "$SCRIPTSDIR/post_init.sh"
. "$SCRIPTSDIR/post_appfs.sh"
. "$SCRIPTSDIR/post_rootfs.sh"
. "$SCRIPTSDIR/post_boot.sh"
. "$SCRIPTSDIR/post_success.sh"

# note we do not unlock after cleanup unless another update
# is expected to run after this one, a fresh boot is needed.
cleanup
rm -rf "$SCRIPTSDIR"

if grep -q POSTACT_POWEROFF "$SWDESC" 2>/dev/null; then
	echo "swupdate triggering poweroff!" >&2
	poweroff
	pkill -9 swupdate
	sleep infinity
elif grep -q POSTACT_WAIT "$SWDESC" 2>/dev/null; then
	echo "swupdate waiting until external reboot" >&2
	sleep infinity
elif needs_reboot; then
	echo "swupdate triggering reboot!" >&2
	reboot
	pkill -9 swupdate
	sleep infinity
elif [ -n "$SWUPDATE_HAWKBIT" ]; then
	unlock_update
	echo "Restarting swupdate-hawkbit service" >&2
	# remove stdout/stderr to avoid sigpipe when parent is killed
	rc-service swupdate-hawkbit restart >/dev/null 2>&1
else
	unlock_update
fi
