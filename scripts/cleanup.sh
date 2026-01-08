#!/bin/sh

# Allow skipping from env
[ -n "$MKSWU_SKIP_SCRIPTS" ] && exit 0

TMPDIR="${TMPDIR:-/var/tmp}"
MKSWU_TMP="$TMPDIR/scripts-mkswu"
# SCRIPTSDIR is overridden for scripts embedded with swupdate
SCRIPTSDIR="$MKSWU_TMP"

. "$SCRIPTSDIR/common.sh"

# run post hook if present
# (we check SWUPDATE_VERSION here to avoid overlapping with
#  the async failure mechanism in scripts/pre_init.sh, and
#  check update_started to avoid running fail script on early
#  version check failures)
if [ -n "$SWUPDATE_VERSION" ] \
    && [ -e "$MKSWU_TMP/update_started" ] \
    && action="$(mkswu_var NOTIFY_FAIL_CMD)" \
    && [ -n "$action" ]; then
	eval "$action"
fi

cleanup
# swupdate removes TMPDIR/scripts itself, but we still
# need to remove mkswu's dir
rm -rf "$MKSWU_TMP"
unlock_update
