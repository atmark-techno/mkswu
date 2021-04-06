#!/bin/sh

OUT=out.swu
CONFIG=./mkimage.conf
FILES="sw-description
sw-description.sig"

usage() {
	echo "usage: $0 [opts]"
	echo
	echo "options:"
	echo "  --config path"
}

error() {
	echo "$@" >&2
	exit 1
}

write_line() {
	local line
	for line; do
		printf "%*s%s\n" "$indent" "" "$line"
	done
}

write_entry() {
	local file_src="$1"
	local file="${file_src##*/}"
	shift
	local sha256 arg install_if

	echo "$FILES" | grep -q -x "$file" || FILES="$FILES
$file"

	if [ -n "$compress" ]; then
		# XXX
		echo "compression not yet handled, ignoring" >&2
	fi

	if [ -n "$encrypt" ]; then
		# XXX
		echo "encryption not yet handled, ignoring" >&2
	fi

	if [ -e "$file.sha256sum" ] && [ "$file.sha256sum" -nt "$file" ]; then
		sha256=$(cat "$file.sha256sum")
	else
		sha256=$(sha256sum < "$file")
		sha256=${sha256%% *}
		echo "$sha256" > "$file.sha256sum"
	fi


	write_line "{"
	indent=$((indent+2))
	write_line "filename = \"$file\";"
	if [ -n "$component" ]; then
		case "$component" in
		uboot|kernel) install_if="different";;
		*) install_if="higher";;
		esac
		write_line "name = \"$component\";"
		[ -n "$version" ] && write_line "version = \"$version\";" \
						"install-if-${install_if} = true;"
	elif [ -n "$version" ]; then
		error "version $version was set without associated component"
	fi
	write_line "$@"

	write_line "sha256 = \"$sha256\";"
	indent=$((indent-2))
	write_line "},"
}

write_entry_component() {
	local component
	local version
	local file="$1"
	shift

	component="${file%% *}"
	file="${file#* }"
	version="${file%% *}"
	file="${file#* }"
	write_entry "$file" "$@"
}

write_uboot() {
	if [ -n "$UBOOT_SIZE" ]; then
		# pad to UBOOT_SIZE to clear environment
		# XXX copy to dest dir
		# XXX check new size is bigger
		truncate -s "$UBOOT_SIZE" "$UBOOT"
	fi
	
	if [ -z "$FORCE" ] && [ -n "$UBOOT_VERSION" ]; then
		strings "$UBOOT" | grep -q -w "$UBOOT_VERSION" || \
			error "uboot version $UBOOT_VERSION was set, but string not present in binary: aborting"
	fi

	component=uboot version=$UBOOT_VERSION \
		write_entry "$UBOOT" "type = \"raw\";" \
			"device = \"/dev/swupdate_ubootdev\";"
}

write_tar() {
	local source="$1"
	local dest="$2"

	write_entry "$source" "type = \"archive\";" "dest = \"/mnt$dest\";"
}

write_tar_component() {
	local source="$1"
	local dest="$2"

	write_entry_component "$source" "type = \"archive\";" "dest = \"/mnt$dest\";"
}

write_files() {
	local file="$1"
	local dest="$2"
	shift
	# other args are source files

	tar -cf "$file.tar" "$@" || error "Could not create tar for $file"
	write_tar "$file.tar" "$dest"
}

write_file_component() {
	local file="$1"
	local dest="$2"

	write_entry_component "$file" "type = \"rawfile\";" \
		"installed-directly = true;" "path = \"/mnt$dest\";"
}

write_sw_desc() {
	local IFS="
"
	local indent=4
	local component
	local version
	local compress
	local encrypt
	local file line tmp_component tmp_version

	cat <<EOF
software = {
  version = "0.1.0";
  description = "Firmware for yakushima";
  hardware-compatibility = [ "1.0" ];
EOF

	for line in $DEBUG_SWDESC; do
		indent=2 write_line $line
	done

	cat <<EOF

  images: (
EOF
	if [ -n "$UBOOT" ]; then
		write_uboot
	fi

	if [ -n "$BASE_OS" ]; then
		component=baseos version=$BASEOS_VERSION compress=1 \
			write_tar "$BASE_OS" "/"
	fi

	if [ -n "$BOOT_FILES" ]; then
		set -- $BOOT_FILES
		component=kernel version=$KERNEL_VERSION \
			write_files boot /boot "$@"
	fi

	for file in $EXTRA_TARS; do
		write_tar_component "$file" "/"
	done

	cat <<EOF
  );
  files: (
EOF
	for file in $EMBED_CONTAINERS; do
		write_file_component "$file" "/var/tmp/${file##*/}"
	done
	cat <<EOF
  );
  scripts: (
EOF

	for script in $EXTRA_SCRIPTS; do
		write_entry_component "$script" "type = \"postinstall\";"
	done

	# swupdate fails if all updates are already installed and there
	# is nothing to do, add a dummy empty script to avoid that
	[ -e empty.sh ] || > empty.sh
	write_entry "empty.sh" "type = \"preinstall\";"

	cat <<EOF
  );
}
EOF
}

make_cpio() {
	openssl dgst -sha256 -sign "$PRIVKEY" -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-2 sw-description > sw-description.sig
	echo "$FILES" | cpio -ov -H crc > $OUT
}

make_image() {
	write_sw_desc > sw-description
	make_cpio
}


while [ $# -ge 1 ]; do
        case "$1" in
	"-c"|"--config")
		[ $# -lt 2 ] && error "$1 requires an argument"
		CONFIG="$2"
		shift 2
		;;
        "-h"|"--help"|"-"*)
                usage
                exit 0
                ;;
        *)
                break
                ;;
        esac
done

. "$CONFIG"

make_image
