#!/bin/bash

# shellcheck disable=SC2043 # loop only runs once ok for style

set -ex

cd "$(dirname "$0")"

"${MKSWU:-../mkswu}" --genkey --cn test --plain --noprompt

. ./common.sh
# install test
SWUPDATE="${SWUPDATE:-swupdate}"
command -v "$SWUPDATE" > /dev/null || error "Need swupdate for this"
HWREV="${HWREV:-/etc/hwrevision}"

# setup/cleanup
cp "$HWREV" /tmp/orig-hwrev
# shellcheck disable=SC2064 # expand now..
trap "mv /tmp/orig-hwrev '$HWREV'" EXIT
echo "iot-g4-es1 at1" > "$HWREV"

# helper
test_install() {
	printf "%s\n" \
			'DEBUG_SWDESC="# DEBUG_SKIP_SCRIPTS"' \
			'swdesc_option FORCE_VERSION' \
			"$@" \
		| name=exec_install build_check - \
		|| error "mkswu build failed"

	"$SWUPDATE" -k ../swupdate.pem -i ./out/exec_install.swu \
		|| error "swupdate failed"
}

test_install "swdesc_exec_nochroot swupdate_exec.sh 'echo \$1 >&2'" \
	"swdesc_exec_nochroot swupdate_exec.sh 'echo again: \$1 >&2'" \
	"MKSWU_TEST_NOT_DIRECTLY=1 swdesc_exec_nochroot swupdate_exec.sh 'echo not direct: \$1 >&2'" \
	"MKSWU_TEST_NOT_DIRECTLY=1 swdesc_exec_nochroot swupdate_exec.sh 'echo not direct again: \$1 >&2'"

# finish with a successful command to not keep last failed on purpose test result
true
