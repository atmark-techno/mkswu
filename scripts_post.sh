#!/bin/sh
# SPDX-License-Identifier: MIT

# shellcheck source-path=SCRIPTDIR/scripts

# Allow skipping from env
if [ -n "$MKSWU_SKIP_SCRIPTS" ]; then
	echo "$0 skipping due to MKSWU_SKIP_SCRIPT" >&2
	exit 0
fi

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

kill_old_swupdate() {
	# We do not want any other swupdate install to run after swupdate
	# stopped
	touch /run/swupdate_rebooting
	# marker in /tmp are kept for compatibility until 2025/04
	# touch -h isn't 100% race-free, use mktemp + mv instead... (ignore errors)
	local tmp
	tmp=$(mktemp /tmp/.swupdate_rebooting.XXXXXX) && mv "$tmp" /tmp/.swupdate_rebooting

	# swupdate >= 2023.12 has better locking, skip this to preserve return status
	[ -n "$SWUPDATE_VERSION" ] && return

	# Kill swupdate and wait to make sure it dies before stopping.
	# This is mostly for hawkbit server, so we do not send success
	# to hawkbit after this script stopped.
	kill -9 $PPID
	while [ -e "/proc/$PPID" ]; do
		sleep 1
	done
}

if [ "$MKSWU_TMP" != "$TMPDIR/scripts" ]; then
	# swupdate removes TMPDIR/scripts itself, but we still
	# need to remove the -vendored dir if it was used...
	rm -rf "$MKSWU_TMP"
fi

case "$post_action" in
poweroff)
	stdout_info_or_error echo "swupdate triggering poweroff!"
	poweroff
	kill_old_swupdate
	;;
wait)
	stdout_info_or_error echo "swupdate waiting until external reboot"
	# tell the world we're ready to be killed
	touch /run/swupdate_waiting
	# marker in /tmp are kept for compatibility until 2025/04
	# touch -h isn't 100% race-free, use mktemp + mv instead... (ignore errors)
	tmp=$(mktemp /tmp/.swupdate_waiting.XXXXXX) && mv "$tmp" /tmp/.swupdate_waiting
	kill_old_swupdate
	;;
container)
	unlock_update
	if [ -n "$SWUPDATE_HAWKBIT" ]; then
		stdout_info_or_error echo "Restarting swupdate-hawkbit service"
		# remove stdout/stderr to avoid sigpipe when parent is killed
		rc-service swupdate-hawkbit restart >/dev/null 2>&1
	else
		info "Container only update done."
	fi
	;;
*)
	stdout_info_or_error echo "swupdate triggering reboot!"
	reboot
	kill_old_swupdate
	;;
esac
