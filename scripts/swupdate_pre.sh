#!/bin/sh

TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPTSDIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

. "$SCRIPTSDIR/common.sh"
. "$SCRIPTSDIR/versions.sh"

. "$SCRIPTSDIR/pre_init.sh"
. "$SCRIPTSDIR/pre_uboot.sh"
. "$SCRIPTSDIR/pre_rootfs.sh"
. "$SCRIPTSDIR/pre_appfs.sh"
