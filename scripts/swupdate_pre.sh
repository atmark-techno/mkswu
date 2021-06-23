#!/bin/sh

TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPTSDIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

. "$SCRIPTSDIR/common.sh"

if [ -e "$TMPDIR/sw-description" ]; then
	SWDESC="$TMPDIR/sw-description"
elif [ -e "/tmp/sw-description" ]; then
	SWDESC="/tmp/sw-description"
else
	error "sw-description not found!"
fi

. "$SCRIPTSDIR/versions.sh"

. "$SCRIPTSDIR/pre_init.sh"
. "$SCRIPTSDIR/pre_uboot.sh"
. "$SCRIPTSDIR/pre_rootfs.sh"
. "$SCRIPTSDIR/pre_appfs.sh"
