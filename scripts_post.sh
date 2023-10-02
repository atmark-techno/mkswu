#!/bin/sh
# SPDX-License-Identifier: MIT

# Allow skipping from env
[ -n "$MKSWU_SKIP_SCRIPTS" ] && exit 0

TMPDIR="${TMPDIR:-/var/tmp}"
MKSWU_TMP="$TMPDIR/scripts"
# SCRIPTSDIR is overridden for scripts embedded with swupdate
SCRIPTSDIR="$MKSWU_TMP"

. "$SCRIPTSDIR/common.sh"
. "$SCRIPTSDIR/post_common.sh"

. "$SCRIPTSDIR/post_init.sh"
. "$SCRIPTSDIR/post_appfs.sh"
. "$SCRIPTSDIR/post_rootfs.sh"
. "$SCRIPTSDIR/post_boot.sh"
. "$SCRIPTSDIR/post_success.sh"

# note we do not unlock after cleanup unless another update
# is expected to run after this one, a fresh boot is needed.
rm -rf "$MKSWU_TMP"

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
	# tell the world we're ready to be killed
	touch /tmp/.swupdate_waiting
	# also forbid other swupdate executions after we're killed
	# while external shutdown happens
	touch /tmp/.swupdate_rebooting
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
