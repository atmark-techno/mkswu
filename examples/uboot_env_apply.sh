#!/bin/sh

# Helper to set uboot env variable permanently
#
# when swupdate is installing an update we cannot just use fw_setenv
# as the config file has not been updated yet.
# force updating it if necessary and run fw_setenv.

usage() {
	echo "Usage: $0 env_file [env_file...]"
	echo
	echo "Set or clear env variable permanently as written in env file"
	echo "(an empty variable clears it)"

}

error() {
	printf "%s\n" "$@" >&2
	exit 1
}

main() {
	case "$1" in
	""|-h|--help) usage; exit 0;;
	esac

	# make sure we run within to be installed target
	local slashdev
	slashdev="$(findmnt -n -o SOURCE /target)"

	[ "${slashdev#/dev/}" != "$slashdev" ] \
		|| error "boot_env.sh script must run in baseos (e.g. swdesc_script_nochroot)"

	# make sure all files exist, prepend /boot/uboot_env.d if appropriate
	for file; do
		if [ "${file#/}" = "$file" ]; then
			# relative path = within uboot_env dir
			file="/target/boot/uboot_env.d/$file"
		else
			file="/target$file"
		fi
		[ -e "$file" ] || error "$file does not exist, failing!"

		# adjust in args
		shift
		set -- "$@" "$file"
	done

	# If that link exists we had a boot image update and default
	# env is not set yet, so fw_setenv will fail.
	# post_boot script will apply these settings for us.
	[ -e /dev/swupdate_bootdev ] && exit 0

	# we want to set env to the to-be-activated partition, so adjust
	# fw_env.config if required e.g. we use mmcblkXbootY partitions
	# with Y being the wrong partition.
	if [ "${slashdev%p[0-9]}" != "$slashdev" ]; then
		local idx="${slashdev##*p}"
		idx=$((idx - 1))
		if grep -qE "mmcblk[0-9]boot$((!idx))" /target/etc/fw_env.config; then
			sed -i -e "s/boot[0-9]/boot$idx/" /target/etc/fw_env.config \
				|| error "Could not update fw_env.config"
		fi
	fi

	# actually set env
	cat "$@" | fw_setenv --config "/target/etc/fw_env.config" --script - \
		|| error "fw_setenv command failed!"
}

main "$@"
