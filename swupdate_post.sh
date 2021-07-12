#!/bin/sh

TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPTSDIR="$TMPDIR/scripts"

. "$SCRIPTSDIR/common.sh"
. "$SCRIPTSDIR/versions.sh"

. "$SCRIPTSDIR/post_init.sh"
. "$SCRIPTSDIR/post_appfs.sh"
. "$SCRIPTSDIR/post_rootfs.sh"
. "$SCRIPTSDIR/post_uboot.sh"

cleanup
rm -rf "$SCRIPTSDIR"

if needs_reboot || [ -n "$force_reboot" ]; then
	echo "swupdate triggering reboot!" >&2
	reboot
fi
