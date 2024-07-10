#!/bin/bash

cd "$(dirname "$0")"

error() {
	printf "%s\n" "$@"
	exit 1
}

check() {
	local expect_rc=$1 expect_txt="$2" rc txt
	shift 2

	txt=$(../mkswu --version-cmp "$@" 2>&1)
	rc="$?"
	[ "$txt" = "$expect_txt" ] \
		|| error "version-cmp $* output '$txt', expected '$expect_txt'"
	[ "$rc" = "$expect_rc" ] \
		|| error "version-cmp $* exited with '$rc' instead of '$expect_rc'"
}

# simple checks
check 0 '1 < 2' 1 2
check 2 '1 < 2' 2 1
check 0 '1.2.3 < 1.2.3.4' 1.2.3 1.2.3.4
check 0 '1.2.3-4 < 1.2.3' 1.2.3-4 1.2.3
check 0 '1-2.3 < 1-2.3.4' 1-2.3 1-2.3.4

# bogus input
check 3 'ERROR: Version 1.2.3.4.5 must be x.y.z.t (numbers < 65536 only) or x.y.z-t (x-z numbers only)' \
	1 1.2.3.4.5

# multiple input
check 0 $'1 < 2\n1 < 3' 1 2 3
check 2 $'1 < 2\n2 < 3' 2 1 3
check 3 $'1 < 2\nERROR: Version 1.2.3.4.5 must be x.y.z.t (numbers < 65536 only) or x.y.z-t (x-z numbers only)\n2 < 3' \
	2 1 1.2.3.4.5 3

# XXX Also run ./swupdate_versions.sh once in a while (on swupdate upgrade?)
