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

needs_reboot && reboot
[ -z "$force_reboot" ] || reboot
