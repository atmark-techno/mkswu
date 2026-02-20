#!/bin/sh
# SPDX-License-Identifier: MIT

# shellcheck source-path=SCRIPTDIR/scripts

# This script prepares the script environment by extracting the
# archive we concatenate at the end of it, then rolls the pre steps.

TMPDIR="${TMPDIR:-/var/tmp}"
MKSWU_TMP="$TMPDIR/scripts-mkswu"
# SCRIPTSDIR is overridden for scripts embedded with swupdate
SCRIPTSDIR="$MKSWU_TMP"

if [ -e "$TMPDIR/sw-description" ]; then
        SWDESC="$TMPDIR/sw-description"
elif [ -e "/var/tmp/sw-description" ]; then
        SWDESC="/var/tmp/sw-description"
elif [ -e "/tmp/sw-description" ]; then
        SWDESC="/tmp/sw-description"
else
        echo "sw-description not found!" >&2
	exit 1
fi

# only cleanup state directories once, if either:
# - running vendored (SCRIPTSDIR changed, runs first)
# - running embedded version and vendored was not run (sw-description not marked for skip)
if [ "$SCRIPTSDIR" != "$MKSWU_TMP" ] \
  || ! grep -q "DEBUG_SKIP_SCRIPTS" "$SWDESC"; then
	if [ "${SWUPDATE_CHAIN_IDX:-1}" = 1 ]; then
		# only re-create dir for first swu in chain,
		rm -rf "$MKSWU_TMP"
		# 2026/02: also remove old scripts dir for leftovers of older SWUs
		# (prints error message if missing so recreate)
		rm -rf "$TMPDIR/scripts"
		mkdir -p "$TMPDIR/scripts"
	else
		if ! [ -e "$MKSWU_TMP" ]; then
			echo "Chained SWU but $MKSWU_TMP does not exist!" >&2
			exit 1
		fi
		# cleanup any certs and re-extract (they are installed
		# after each individual swu if present)
		# 2026/02: also remove old scripts dir for leftovers of older SWUs
		rm -rf "$MKSWU_TMP/certs_"* \
			"$TMPDIR/scripts/certs_"*
	fi
fi

mkdir -p "$MKSWU_TMP" || exit 1
cd "$MKSWU_TMP" || exit 1

# remember if we're running vendored or not for post_rootfs script
# (vendored has a different SCRIPTSDIR)
if [ "$SCRIPTSDIR" != "$MKSWU_TMP" ]; then
	touch "vendored"
else
	# also remove it for chained update alternating vendored or not...
	rm -f "vendored"
fi

# extract archive after script
sed -e '1,/^BEGIN_ARCHIVE/d' "$0" | tar xv || exit 1

# Allow skipping from env
if [ -n "$MKSWU_SKIP_SCRIPTS" ]; then
	echo "$0 skipping due to MKSWU_SKIP_SCRIPTS" >&2
	exit 0
fi

# prepare update
. "$SCRIPTSDIR/common.sh"
. "$SCRIPTSDIR/versions.sh"

. "$SCRIPTSDIR/pre_init.sh"
. "$SCRIPTSDIR/pre_boot.sh"
. "$SCRIPTSDIR/pre_rootfs.sh"
. "$SCRIPTSDIR/pre_appfs.sh"

exit
# This must be the last line!
# shellcheck disable=SC2317 # (unreachable after exit)
BEGIN_ARCHIVE
