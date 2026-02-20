#!/bin/sh
# SPDX-License-Identifier: MIT

# shellcheck source-path=SCRIPTDIR/scripts

# This script prepares the script environment by extracting the
# archive we concatenate at the end of it, then rolls the pre steps.

TMPDIR="${TMPDIR:-/var/tmp}"
MKSWU_TMP="$TMPDIR/scripts-mkswu"
# SCRIPTSDIR is overridden for scripts embedded with swupdate
SCRIPTSDIR="$MKSWU_TMP"

if [ "${SWUPDATE_CHAIN_IDX:-1}" = 1 ]; then
	# only re-create dir for first swu in chain
	rm -rf "$MKSWU_TMP"
	mkdir "$MKSWU_TMP" || exit 1
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
	# Note scripts-mkswu is hardcoded as we only consider the
	# SWU tarball.
	# 2026/02: also remove old scripts dir for leftovers of older SWUs
	rm -rf "$TMPDIR/scripts-mkswu/certs_"* \
		"$TMPDIR/scripts/certs_"*
fi

cd "$MKSWU_TMP" || exit 1

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
