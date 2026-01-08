#!/bin/sh

TMPDIR="${TMPDIR:-/var/tmp}"
MKSWU_TMP="$TMPDIR/scripts-mkswu"
# SCRIPTSDIR is overridden for scripts embedded with swupdate
SCRIPTSDIR="$MKSWU_TMP"

# Allow skipping from env
if [ -n "$MKSWU_SKIP_SCRIPTS" ]; then
	rm -rf "$MKSWU_TMP"
	exit 0
fi

. "$SCRIPTSDIR/common.sh"

handle_chained_swu() {
	# Updates with nothing to do are considered failures by swupdate,
	# but we don't want this script to run for chained updates in this
	# case, so check manually...

	# We still want to cleanup $TMPDIR/scripts-vendored on nothing
	# to do if this was not a chained update, so we only check this on chained update
	[ -n "$SWUPDATE_CHAIN_IDX" ] || return

	# Not nothing to do -> real error, cleanup normally
	[ -e "$MKSWU_TMP/nothing_to_do" ] || return

	# not last in chain, don't cleanup.
	[ "$SWUPDATE_CHAIN_IDX" != "$SWUPDATE_CHAIN_COUNT" ] && exit

	# last in chain, run post to finish update.
	# (but still need cleanup if that failed...
	# hence subshell to catch if it exists)
	( "$SCRIPTSDIR/post.sh"; ) && exit 0
}

do_cleanup() {
	handle_chained_swu

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
}

do_cleanup
