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
rm -rf "$SCRIPTSDIR"

POST_ACTION=$(post_action)
case "$POST_ACTION" in
poweroff)
	stdout_info_or_error echo "swupdate triggering poweroff!"
	touch /tmp/.swupdate_rebooting
	poweroff
	pkill -9 swupdate
	sleep infinity
	;;
wait)
	stdout_info_or_error echo "swupdate waiting until external reboot"
	# we rely on normal lock for this case:
	# if a user wants to kill swupdate and reinstall a new install
	# it is somewhat valid, although previous update will be lost
	sleep infinity
	;;
container)
	unlock_update
	if [ -n "$SWUPDATE_HAWKBIT" ]; then
		stdout_info_or_error echo "Restarting swupdate-hawkbit service"
		# remove stdout/stderr to avoid sigpipe when parent is killed
		rc-service swupdate-hawkbit restart >/dev/null 2>&1
	fi
	;;
*)
	stdout_info_or_error echo "swupdate triggering reboot!"
	touch /tmp/.swupdate_rebooting
	reboot
	pkill -9 swupdate
	sleep infinity
	;;
esac
