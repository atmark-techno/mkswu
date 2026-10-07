#!/bin/bash

# shellcheck disable=SC2043 # loop only runs once ok for style

set -ex

cd "$(dirname "$0")"

"${MKSWU:-../mkswu}" --genkey --cn test --plain --noprompt

. ./common.sh
# install test
SWUPDATE="${SWUPDATE:-swupdate}"
command -v "$SWUPDATE" > /dev/null || error "Need swupdate for this"
SW_VERSIONS="${SW_VERSIONS:-/etc/sw-versions}"
HWREV="${HWREV:-/etc/hwrevision}"
export MKSWU_SKIP_SCRIPTS=1
[ -w "$SW_VERSIONS" ] || error "sw-versions didn't exist (or not writable), bad path?"

# setup/cleanup
cp "$SW_VERSIONS" /tmp/orig-sv-versions
cp "$HWREV" /tmp/orig-hwrev
# shellcheck disable=SC2064 # expand now..
trap "mv /tmp/orig-sv-versions '$SW_VERSIONS'; mv /tmp/orig-hwrev '$HWREV'" EXIT
echo "iot-g4-es1 at1" > "$HWREV"


# helper
test_version_install() {
	local oldvers="$1" newvers="$2"
	local canary=/tmp/swupdate-installed
	local swupdate_component=${swupdate_component:-testcomp}
	local install_if="${install_if:-}"
	local normalized_newvers
	# shellcheck disable=SC2016 ## single quote on purpose...
	normalized_newvers=$(version="$newvers" "$MKSWU" --internal \
			eval 'normalize_version; echo $version') \
		&& [ -n "$normalized_newvers" ] \
		|| error "Could not normalize version"
	shift 2 # extra args extra swdesc arguments

	printf "%s\n" \
			"${install_if:+swdesc_option install_if=$install_if}" \
			"swdesc_command_nochroot --version testcomp '$newvers' \\" \
			"	'touch \"$canary\"'" \
		| name=version_install build_check - -- "swdesc 'VERSION testcomp ${normalized_newvers/+/\\+}'" \
		|| error "mkswu build failed"

	echo "$swupdate_component $oldvers" > "$SW_VERSIONS"
	rm -f "$canary"
	"$SWUPDATE" -k ../swupdate.pem -i ./out/version_install.swu \
		|| error "swupdate failed"
	[ -e "$canary" ]
	local rc=$?
	rm -f "$canary"

	# check mkswu agrees
	# ...if no extra config (e.g. install_if=different)
	[ "$install_if" = different ] && return $rc
	# ... also swupdate_component=other means we compare against no old version:
	# current code hardcodes any value > '' so skip
	if [ "$swupdate_component" != testcomp ]; then
		[ "$rc" = 0 ] || error "mkswu scripts require empty value < anything, but swupdate had '' >= $newvers"
		return 0
	fi
	../mkswu --version-cmp "$oldvers" "$newvers"
	local mkswu_rc=$?
	case "$rc,$mkswu_rc" in
	0,0|1,2) ;; # ok
	*,3) error "version invalid for mkswu: '$oldvers' / '$newvers'";;
	0,2) error "mkswu and swupdate didn't agree (swupdate '$oldvers' < '$newvers')";;
	1,0) error "mkswu and swupdate didn't agree (swupdate '$oldvers' >= '$newvers')";;
	*) error "Unexpected swupdate rc $rc mkswu $mkswu_rc ('$oldvers' / '$newvers')";;
	esac

	return $rc
}
test_installed() {
	local old="$1" new="$2"
	shift 2
	test_version_install "$old" "$new" "$@" \
		|| error "$new was installed over than $old (${install_if:+install_if=$install_if}${swupdate_component:+component=$swupdate_component})"
}
test_skipped() {
	local old="$1" new="$2"
	shift 2
	! test_version_install "$old" "$new" "$@" \
		|| error "$new was incorrectly installed over $old (${install_if:+install_if=$install_if}${swupdate_component:+component=$swupdate_component})"
}


# versions higher than base
test_installed 1 2
test_installed 1 1.1

test_installed 1.1.1-1.abc 1.1.1
test_installed 1.1.1-1.abc 1.1.2
test_installed 1.1.1-1.abc 1.2
test_installed 1.1.1-1.abc 2
test_installed 1.1.1-1.abc 1.1.1-2
test_installed 1.1.1-1.abc 1.1.1-1.abd
test_installed 1.1.1-1.abc 1.1.1-1.b
test_installed 1.1.1-1.abc 1.1.1-abc
test_installed 1.1.1-1.abc 1.1.1-1.abc.0

# versions lower or equal than base
test_skipped 1 1
test_skipped 1 1.0
test_skipped 1 1-0
test_skipped 1 0

test_skipped 1.1.1-1.abc 1
test_skipped 1.1.1-1.abc 1.1.0
test_skipped 1.1.1-1.abc 1.1.1-0
test_skipped 1.1.1-1.abc 1.1.1-1.a
test_skipped 1.1.1-1.abc 1.1.1-1.1
test_skipped 1.1.1-1.abc.0 1.1.1-1.abc
test_skipped 1.1-1 1.1.0-1

# weird identical semvers...
test_skipped 1.1-1..1 1.1-1.0.1
test_skipped 1.1-1.0.1 1.1-1..1
test_skipped 1.1-1.. 1.1-1.0.0
test_skipped 1.1-1.0.0 1.1-1..

# test semvers with +
test_installed '2.1-4+4' '2.1-5+2'
test_skipped '2.1-4+4' '2.1-4+6afdsb-43214.2341--afsd34'
test_skipped '2.1-4' '2.1-4+6afdsb-43214.2341--afsd34'
test_skipped '2.1-4+4' '2.1-4'

# tests if different as well
# different versions
install_if=different test_installed 1 2
install_if=different test_installed 1 1.1
install_if=different test_installed 1 1-0
install_if=different test_installed 1 0x1

install_if=different test_installed 1.1.1 1.1.1.1
install_if=different test_installed 1.1.1 1.1.2
install_if=different test_installed 1.1.1 1.1.1-0

install_if=different test_installed 1.1-0 1.1-0.0
install_if=different test_installed 1.1-0 1.1-1

# not allowed for higher, but uboot's different can have multiple dashes
install_if=different test_installed 1.1-01-01 1.1-01-1
install_if=different test_installed 1.1-01-01 1.1-1-01

# identical versions
install_if=different test_skipped 1 1
install_if=different test_skipped 1 1.0
install_if=different test_skipped 1 01
install_if=different test_skipped 1 1.00

install_if=different test_skipped 1.1-1 1.1.0-1
install_if=different test_skipped 1.1-1 1.01-1
install_if=different test_skipped 1.1-1 1.1-01

# version missing in swupdate, all should be upgrade
swupdate_component=other test_installed 1 1
swupdate_component=other test_installed 1 0

# from here, test things that normally aren't allowed just to see...
export MKSWU_TEST_ALLOW_BOGUS_VERSION=1

# negative version (should be handled as string)
swupdate_component=other test_installed 1 "-1"

# finish with a successful command to not keep last failed on purpose test result
true
