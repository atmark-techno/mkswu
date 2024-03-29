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

kill_swupdate() {
	# We do not want any other swupdate install to run after swupdate
	# stopped
	touch /tmp/.swupdate_rebooting
	# Kill swupdate and wait to make sure it dies before stopping.
	# This is mostly for hawkbit server, so we do not send success
	# to hawkbit after this script stopped.
	kill -9 $PPID
	while [ -e "/proc/$PPID" ]; do
		sleep 1
	done
}

case "$post_action" in
poweroff)
	stdout_info_or_error echo "swupdate triggering poweroff!"
	poweroff
	kill_swupdate
	;;
wait)
	stdout_info_or_error echo "swupdate waiting until external reboot"
	# tell the world we're ready to be killed
	touch /tmp/.swupdate_waiting
	kill_swupdate
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
	reboot
	kill_swupdate
	;;
esac
