#!/bin/sh

OUT=out.swu
CONFIG=./mkimage.conf
FILES="sw-description
sw-description.sig"
PRIVKEY=swupdate.key
UBOOT=""
UBOOT_VERSION=""
UBOOT_SIZE="4M"
BOOT_FILES=""
KERNEL_VERSION=""
BASE_OS=""
BASE_OS_VERSION=""
EXTRA_OS=""
EXTRA_OS_VERSION=""
PRE_SCRIPTS=""
POST_SCRIPTS=""
UPDATE_CONTAINERS=""
EMBED_CONTAINERS=""
DEBUG_SWDESC="# ATMARK_FLASH_DEV /dev/mmcblk2
# ATMARK_FLASH_AB 0"
FORCE=1

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

write_one_file() {
	local file_src="$1"
	local file="${file_src##*/}"
	shift
	local sha256 arg

	echo "$FILES" | grep -q -x "$file" || FILES="$FILES
$file"

	if [ -n "$compress" ]; then
		echo "compression not yet handled, ignoring" >&2
	fi

	if [ -n "$encrypt" ]; then
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
		write_line "name = \"$component\";"
		[ -n "$version" ] && write_line "version = \"$version\";" \
						"install-if-different = true;"
	elif [ -n "$version" ]; then
		error "version $version was set without associated component"
	fi
	write_line "$@"

	write_line "sha256 = \"$sha256\";"
	indent=$((indent-2))
	write_line "},"
}

write_uboot() {
	if [ -n "$UBOOT_SIZE" ]; then
		# pad to UBOOT_SIZE to clear environment
		# XXX copy to dest dir
		truncate -s "$UBOOT_SIZE" "$UBOOT"
	fi
	
	if [ -z "$FORCE" ] && [ -n "$UBOOT_VERSION" ]; then
		strings "$UBOOT" | grep -q -w "$UBOOT_VERSION" || \
			error "uboot version $UBOOT_VERSION was set, but string not present in binary: aborting"
	fi

	component=uboot version=$UBOOT_VERSION \
		write_one_file "$UBOOT" "type = \"raw\";" \
			"device = \"/dev/swupdate_ubootdev\";"
}

write_tar() {
	local source="$1"
	local dest="$2"

	write_one_file "$source" "type = \"archive\";" "dest = \"/mnt$dest\";"
}

write_files() {
	local file="$1"
	local dest="$2"
	shift
	# other args are source files

	tar -cf "$file.tar" "$@" || error "Could not create tar for $file"
	write_tar "$file.tar" "$dest"
}

write_file() {
	local file="$1"
	local dest="$2"

	write_one_file "$file" "type = \"rawfile\";" \
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
	local file line

	cat <<EOF
software = {
  version = "0.1.0";
  description = "Firmware for yakushima";
  hardware-compatibility = [ "1.0" ];
EOF

	for line in $DEBUG_SWDESC; do
		indent=2 write_line $line
	done
	if [ -n "$UPDATE_CONTAINERS" ]; then
		indent=2 write_line "# ATMARK_CONTAINERS_UPDATE $UPDATE_CONTAINERS"
	fi

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

	for file in $EXTRA_OS; do
		component=extra_os version=$EXTRA_OS_VERSION \
			write_tar "$file" "/"
	done

	cat <<EOF
  );
  files: (
EOF
	for file in $EMBED_CONTAINERS; do
		# XXX assing component/version per file somehow
		write_file "$file" "/var/tmp/${file##*/}"
	done
	cat <<EOF
  );
  scripts: (
EOF

	for script in $PRE_SCRIPTS; do
		write_one_file "$script" "type = \"preinstall\";"
	done
	for script in $POST_SCRIPTS; do
		write_one_file "$script" "type = \"postinstall\";"
	done

	# swupdate fails if all updates are already installed and there
	# is nothing to do, add a dummy empty script to avoid that
	[ -e empty.sh ] || > empty.sh
	write_one_file "empty.sh" "type = \"preinstall\";"

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
