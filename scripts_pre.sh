#!/bin/sh
# SPDX-License-Identifier: MIT

# This script prepares the script environment by extracting the
# archive we concatenate at the end of it, then rolls the pre steps.

TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPTSDIR="$TMPDIR/scripts"

rm -rf "$SCRIPTSDIR"
mkdir "$SCRIPTSDIR" || exit 1
cd "$SCRIPTSDIR" || exit 1

# extract archive after script
sed -e '1,/^BEGIN_ARCHIVE/d' "$0" | tar xv || exit 1

# prepare update
. "./common.sh"
. "./versions.sh"

. "./pre_init.sh"
. "./pre_boot.sh"
. "./pre_rootfs.sh"
. "./pre_appfs.sh"

exit
# This must be the last line!
BEGIN_ARCHIVE
