#!/bin/sh

# install kernel for kernel_update_plain.desc

error() {
	printf "%s\n" "$@" >&2
	exit 1
}

usage() {
	echo "Usage: $0 [DEST]"
	echo
	echo "DEST defaults to ~/mkswu"
	echo "Must run from linux build directory"
	exit
}

update_desc() {
	local version
	version="${kver%%-*}"

	if ! [ -e "$desc" ]; then
		[ -e "$desc_template" ] \
			|| error "Template desc file for kernel does not exist: $desc_template"
		cp "$desc_template" "$desc" \
			|| error "Could not copy $desc_template to $desc"
	fi

	# update version (this also creates .old backup)
	"$mkswu" --update-version --version-base "$version" "$desc" \
		|| error "Could not update kernel version in $desc"

	# update KERNEL_INSTALL/IMAGE if required
	if ! grep -qFx "KERNEL_INSTALL=${dest##*/}" "$desc"; then
		sed -i -e 's/^KERNEL_INSTALL=.*/KERNEL_INSTALL='"${dest##*/}"'/' "$desc" \
			|| error "Could not update KERNEL_INSTALL in $desc"
	fi
	if ! grep -qFx "KERNEL_IMAGE=${image##*/}" "$desc"; then
		sed -i -e 's/^KERNEL_IMAGE=.*/KERNEL_IMAGE='"${image##*/}"'/' "$desc" \
			|| error "Could not update KERNEL_IMAGE in $desc"
	fi
}

install() {
	local desc="$1" arch cross
	local dest image dtb_prefix modalias kver
	local examples_dir mkswu
	examples_dir="$(dirname "$(realpath "$0")")"
	local desc_template="$examples_dir/kernel_update_plain.desc"

	[ -n "$desc" ] && [ "${desc%.desc}" = "$desc" ] \
		&& error "Destination $desc should end in .desc"
	[ -e Kbuild ] || error "Please run from linux build directory"
	[ -e vmlinux ] || error "Please build kernel first"
	if [ -x "$examples_dir/../mkswu" ]; then
		mkswu="$examples_dir/../mkswu"
	elif command -v mkswu >/dev/null; then
		mkswu=mkswu
	else
		error "mkswu not found (required for version update)"
	fi
	[ "$#" -le 1 ] || error "Extra argument: $2"

	# guess target based on config arch
	arch=$(grep -oE 'Linux/[a-z0-9]*' -m 1 .config) \
		|| error "Could not read arch from .config"
	arch=${arch#Linux/}
	case "$arch" in
	arm64)
		image=arch/arm64/boot/Image
		dtb_prefix=arch/arm64/boot/dts/freescale/armadillo_
		cross=${CROSS_COMPILE:-aarch64-linux-gnu-}
		;;
	arm)
		image=arch/arm/boot/uImage
		dtb_prefix=arch/arm/boot/dts/armadillo-
		cross=${CROSS_COMPILE:-arm-linux-gnueabihf-}
		;;
	*)
		error "Unhandled arch $arch"
		;;
	esac

	[ -e "$image" ] \
		|| error "Build incomplete: missing $image"
	# shellcheck disable=SC3013 # -nt available in dash
	[ "$image" -nt vmlinux ] \
		|| error "vmlinux should not be newer than $image, did you rebuild everything ?"

	# We need desc to contain a / for ${desc%/*} and similar substitutions
	case "$desc" in
	*/*) ;;
	"") desc="$HOME/mkswu/kernel-$arch.desc";;
	*) desc="./$desc"
	esac
	dest="${desc%.desc}"
	[ -d "${desc%/*}" ] || error "Please create destination directory ${desc%/*}"

	if [ -e "$dest" ]; then
		echo "Purging $dest ..."
		rm -rf "$dest"
	fi
	echo "Installing kernel in $dest ..."
	mkdir "$dest" \
		|| error "Could not create destination $dest"

	# install kernel
	cp -v "$image" "$dest/" \
		|| error "Could not copy linux image $image"
	cp -v "$dtb_prefix"*.dtb "$dtb_prefix"*.dtbo "$dest/" \
		|| error "Could not copy dtb files $dtb_prefix*.{dtb,dtbo}"
	make ARCH="$arch" CROSS_COMPILE="$cross" \
			INSTALL_MOD_PATH="$dest" modules_install \
		|| error "Could not install modules"

	# get version and sanity checks
	kver=""
	for modalias in "$dest"/lib/modules/*/modules.alias.bin; do
		[ -e "$modalias" ] \
			|| error "depmod did not run on module install"
		[ -z "$kver" ] \
			|| error "Multiple kernel versions in $dest/lib/modules, modules_install did not work as expected?"
		kver="${modalias%/modules.alias.bin}"
		kver="${kver##*/}"
	done
	[ "$(stat -c %s "$modalias")" -gt 1000 ] \
		|| error "module alias $modalias is suspiciously small, check module loading"
	strings "$image" | grep -qxF "$kver" \
		|| error "Could not find exact version $kver in $image, is build up to date?"

	update_desc

	echo "Done installing kernel, run \`mkswu \"$desc\"\` next."
}

install "$@"
