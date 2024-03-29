#!/bin/bash

# install kernel for kernel_update_plain.desc

# TEXTDOMAIN / TEXTDOMAINDIR need to be set at toplevel or bash ignores them
SCRIPT_DIR="$(realpath -P "$0")" || error $"Could not get script dir"
SCRIPT_BASE="${0##*/}"
[[ "$SCRIPT_DIR" = "/" ]] || SCRIPT_DIR="${SCRIPT_DIR%/*}"
case "$SCRIPT_DIR" in
/usr/share*) :;;
*) TEXTDOMAINDIR="$SCRIPT_DIR/../locale";;
esac
TEXTDOMAIN=mkswu_kernel_update_plain

error() {
	printf "ERROR: %s\n" "$@" >&2
	exit 1
}

usage() {
	echo $"Usage: $0 [--force] [DEST]"
	echo
	echo $"DEST defaults to ~/mkswu/kernel-[arch].desc"
	echo $"Must run from linux build directory"
	echo
	echo $"Use --force to disable build sanity checks"
	exit
}

preinstall_checks() {
	[ -n "$desc" ] && [ "${desc%.desc}" = "$desc" ] \
		&& error $"Destination $desc should end in .desc"
	# (for out of tree build Kbuild might not exist, this is fine)
	[ -e Kbuild ] || [ -e vmlinux ] \
		|| error $"Please run from linux build directory"
	[ -e vmlinux ] || error $"Please build kernel first"
	if [ -x "$examples_dir/../mkswu" ]; then
		mkswu="$examples_dir/../mkswu"
	elif command -v mkswu >/dev/null; then
		mkswu=mkswu
	else
		error $"mkswu not found (required for version update)"
	fi

	# guess target based on config arch
	arch=$(grep -oE 'Linux/[a-z0-9]*' -m 1 .config) \
		|| error $"Could not read arch from .config"
	arch=${arch#Linux/}
	case "$arch" in
	arm64)
		image=arch/arm64/boot/Image
		version_check_prefix=""
		dtb_prefix=arch/arm64/boot/dts/freescale/armadillo_
		cross=${CROSS_COMPILE:-aarch64-linux-gnu-}
		;;
	arm)
		image=arch/arm/boot/uImage
		# actual uname -r can be garbled by uImage packing,
		# use Linux-XXX in uImage headers instead
		version_check_prefix=Linux-
		dtb_prefix=arch/arm/boot/dts/armadillo-
		cross=${CROSS_COMPILE:-arm-linux-gnueabihf-}
		;;
	*)
		error $"Unhandled arch $arch"
		;;
	esac

	[ -e "$image" ] \
		|| error $"Build incomplete: missing $image"

	# We need desc to contain a / for ${desc%/*} and similar substitutions
	case "$desc" in
	*/*) ;;
	"") desc="$HOME/mkswu/kernel-$arch.desc";;
	*) desc="./$desc"
	esac
	dest="${desc%.desc}"
	[ -d "${desc%/*}" ] || error $"Please create destination directory ${desc%/*}"

	if [ -e "$desc" ] \
	    && ! grep -q "version is automatically updated from kernel_update_plain.install.sh" "$desc"; then
		error $"Existing .desc file $desc is too old, please remove it and" \
			$"adjust version after installing if required"
	fi

	# Optional checks from here
	[ -n "$nocheck" ] && return

	# shellcheck disable=SC3013 # -nt available in dash
	[ "$image" -nt vmlinux ] \
		|| error $"vmlinux should not be newer than $image, did you rebuild everything ?"
}

install_files() {
	if [ -e "$dest" ]; then
		echo $"Purging $dest ..."
		rm -rf "$dest"
	fi
	echo $"Installing kernel in $dest ..."
	mkdir "$dest" \
		|| error $"Could not create destination $dest"

	# install kernel
	cp -v "$image" "$dest/" \
		|| error $"Could not copy linux image $image"
	cp -v "$dtb_prefix"*.dtb "$dtb_prefix"*.dtbo "$dest/" \
		|| error $"Could not copy dtb files $dtb_prefix*.{dtb,dtbo}"
	make ARCH="$arch" CROSS_COMPILE="$cross" \
			INSTALL_MOD_PATH="$dest" modules_install \
		|| error $"Could not install modules"
}

postinstall_checks() {
	[ -n "$nocheck" ] && return
	# get version and sanity checks
	kver=""
	for modalias in "$dest"/lib/modules/*/modules.alias.bin; do
		[ -e "$modalias" ] \
			|| error $"depmod did not run on module install"
		[ -z "$kver" ] \
			|| error $"Multiple kernel versions in $dest/lib/modules, modules_install did not work as expected?"
		kver="${modalias%/modules.alias.bin}"
		kver="${kver##*/}"
	done
	[ "$(stat -c %s "$modalias")" -gt 1000 ] \
		|| error $"module alias $modalias is suspiciously small, assuming depmod failed to parse modules" \
			 $"Please check CONFIG_MODULE_COMPRESS is unset"
	strings "$image" | grep -qxF "$version_check_prefix$kver" \
		|| error $"Could not find exact version $kver in $image, is build up to date?"

}

update_desc() {
	local version
	version="${kver%%-*}"

	if ! [ -e "$desc" ]; then
		[ -e "$desc_template" ] \
			|| error $"Template desc file for kernel does not exist: $desc_template"
		cp "$desc_template" "$desc" \
			|| error $"Could not copy $desc_template to $desc"
	fi

	# update version (this also creates .old backup)
	"$mkswu" --update-version --version-base "$version" "$desc" \
		|| error $"Could not update kernel version in $desc"

	# update KERNEL_INSTALL/IMAGE if required
	if ! grep -qFx "KERNEL_INSTALL=${dest##*/}" "$desc"; then
		sed -i -e 's/^KERNEL_INSTALL=.*/KERNEL_INSTALL='"${dest##*/}"'/' "$desc" \
			|| error $"Could not update KERNEL_INSTALL in $desc"
	fi
	if ! grep -qFx "KERNEL_IMAGE=${image##*/}" "$desc"; then
		sed -i -e 's/^KERNEL_IMAGE=.*/KERNEL_IMAGE='"${image##*/}"'/' "$desc" \
			|| error $"Could not update KERNEL_IMAGE in $desc"
	fi
}

install() {
	local desc arch cross
	local dest image dtb_prefix modalias kver
	local examples_dir mkswu nocheck=""
	examples_dir="$(dirname "$(realpath "$0")")"
	local desc_template="$examples_dir/kernel_update_plain.desc"

	case "$1" in
	--force) nocheck=1; shift;;
	--help|-h) usage;;
	esac
	desc="$1"

	[ "$#" -le 1 ] || error $"Extra argument: $2"

	preinstall_checks
	install_files
	postinstall_checks
	update_desc

	echo $"Done installing kernel, run \`mkswu \"$desc\"\` next."
}

install "$@"
