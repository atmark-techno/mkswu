#!/bin/bash

set -e

# build examples swu and check basic things (e.g. version included in sw-description)

. scripts/versions.sh

error() {
	echo "$@" >&2
	exit 1
}

check() {
	local type="$1"
	local file tar
	local component version real_version
	shift
	case "$type" in
	file)
		(( $# > 0 )) || error "file check has no argument"
		for file; do
			cpio -t < "$name".swu | grep -qx "$file" ||
				error "$file not in swu"
		done
		;;
	file-tar)
		(( $# > 1 )) || error "file-tar needs tar and content args"
		tar="$1"
		shift
		tar tf "$name/$tar" "$@" > /dev/null || error "Missing files in $tar"
		;;
	version)
		(( $# == 2 )) || error "version usage: <component> <version regex>"
		component="$1"
		version="$2"

		## from scripts/version.sh gen_newversion:
		parse_swdesc < "$name/sw-description" > "$name/sw-versions.present"
		real_version=$(get_version "$component" "$name/sw-versions.present")

		[[ "$real_version" =~ $version ]] ||
			error "Version $component expected $version got $real_version"
		;;
	*) error "Unknown check type: $type" ;;
	esac
}

build_check() {
	local name="$1"
	local check
	shift

	echo "Building $name"
	./mkimage.sh -o "$name.swu" "examples/$name.conf"

	for check; do
		check $check
	done
}

# custom script: no prereq
build_check custom_script "file custom_script_app.sh"

# sshd: build tar
tar -C examples/enable_sshd -cf examples/enable_sshd.tar .
build_check enable_sshd "version extra_os .+" "file enable_sshd_genkeys.sh" "file-tar enable_sshd.tar.zst ./etc/runlevels/default/sshd ./root/.ssh/authorized_keys"

# pull container: build tar
tar -C examples/nginx_start -cf examples/nginx_start.tar .
build_check pull_container_nginx "file-tar nginx_start.tar.zst ./etc/atmark/containers/nginx.conf" "file container_docker_io_nginx_alpine.pull"

# uboot: prereq fullfilled by yakushima tar
build_check uboot "file imx-boot_yakushima-eva.zst" "version uboot 202.*"

# kernel plain: just a couple of files.. since we don't actually check installation create dummy ones
touch Image imx8mp-yakushima-eva.dtb
build_check kernel_update_plain "file-tar boot.tar.zst Image imx8mp-yakushima-eva.dtb"

# kernel apk: likewise we don't actually test install here,
touch examples/linux-at-5.10.9-r3.apk
build_check kernel_update_apk "file linux-at-5.10.9-r3.apk"
