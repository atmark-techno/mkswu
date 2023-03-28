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
	local canary=/tmp/swupdate-installed rc
	local normalized_newvers
	# shellcheck disable=SC2016 ## single quote on purpose...
	normalized_newvers=$(version="$newvers" "$MKSWU" --internal \
			eval 'normalize_version; echo $version') \
		&& [ -n "$normalized_newvers" ] \
		|| error "Could not normalize version"
	shift 2 # extra args extra swdesc arguments
	printf "%s\n" \
			'DEBUG_SWDESC="# DEBUG_SKIP_SCRIPTS"' \
			"$@" \
			"swdesc_command_nochroot --version testcomp '$newvers' \\" \
			"	'touch \"$canary\"'" \
		| name=version_install build_check - -- "swdesc 'VERSION testcomp $normalized_newvers'" \
		|| error "mkswu build failed"

	echo "testcomp $oldvers" > "$SW_VERSIONS"
	rm -f "$canary"
	"$SWUPDATE" -k ../swupdate.pem -i ./out/version_install.swu \
		|| error "swupdate failed"
	[ -e "$canary" ]
	rc=$?
	rm -f "$canary"

	return $rc
}

# versions higher than base
base=1
for version in 2 1.1; do
        test_version_install "$base" "$version" \
                || error "$version was not higher than $base"
done
base=1.1.1-1.abc
for version in 1.1.1 1.1.2 1.2 2 1.1.1-2 1.1.1-1.abd 1.1.1-1.b; do
        test_version_install "$base" "$version" \
                || error "$version was not higher than $base"
done
# versions lower or equal than base
base=1
for version in 1 1.0 1-0 0; do
        test_version_install "$base" "$version" \
                && error "$version was higher than $base"
done
base=1.1.1-1.abc
for version in 1 1.1.0 1.1.1-0 1.1.1-1.a; do
        test_version_install "$base" "$version" \
                && error "$version was higher than $base"
done
base=1.1-1
for version in 1.1.0-1; do
        test_version_install "$base" "$version" \
                && error "$version was higher than $base"
done


# tests if different as well
# different versions
base=1
for version in 2 1.1 1-0 0x1; do
	test_version_install "$base" "$version" \
			'swdesc_option install_if=different' \
		|| error "$base was same as $version..."
done
base=1.1.1
for version in 1.1.1.1 1.1.2 1.1.1-0; do
	test_version_install "$base" "$version" \
			'swdesc_option install_if=different' \
		|| error "$base was same as $version..."
done
base=1.1-0
for version in 1.1-0.0 1.1-1; do
	test_version_install "$base" "$version" \
			'swdesc_option install_if=different' \
		|| error "$base was same as $version..."
done
# not allowed for higher, but uboot's different can have multiple dashes
base=1.1-01-01
for version in 1.1-01-1 1.1-1-01; do
	test_version_install "$base" "$version" \
			'swdesc_option install_if=different' \
		|| error "$base was same as $version..."
done

# identical versions
base=1
for version in 1 1.0 01 1.00; do
	test_version_install "$base" "$version" \
			'swdesc_option install_if=different' \
		&& error "$base was not equal to $version"
done
base=1.1-1
for version in 1.1.0-1 1.01-1 1.1-01; do
	test_version_install "$base" "$version" \
			'swdesc_option install_if=different' \
		&& error "$base was not equal to $version"
done

# finish with a successful command to not keep last failed on purpose test result
true
