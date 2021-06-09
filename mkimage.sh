#!/bin/sh

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
OUT=out.swu
OUTDIR=out
CONFIG=./mkimage.conf
EMBEDDED_SCRIPTS_DIR="$SCRIPT_DIR/scripts"
PRE_SCRIPT="swupdate_pre.sh"
POST_SCRIPT="$SCRIPT_DIR/swupdate_post.sh"
FILES="sw-description
sw-description.sig"

usage() {
	echo "Usage: $0 [opts]"
	echo
	echo "Options:"
	echo "  -c, --config  path"
	echo "  -o, --out     path.swu"
}

error() {
	local line
	for line; do
		echo "$line" >&2
	done
	exit 1
}

write_line() {
	local line
	for line; do
		printf "%*s%s\n" "${line:+$indent}" "" "$line"
	done
}

link() {
	local src="$1"
	local dest="$2"
	local existing

	src=$(readlink -e "$src") || error "Cannot find source file: $1"

	if [ -e "$dest" ]; then
		existing=$(readlink "$dest")
		[ "$src" = "$existing" ] && return 1
		rm -f "$dest"
	fi
	ln -s "$(readlink -e "$src")" "$dest" || error "Could not link to $src"
}

gen_iv() {
	openssl rand -hex 16
}

encrypt_file() {
	local src="$1"
	local dest="$2"
	local iv

	iv=$(gen_iv) || return 1
	openssl enc -aes-256-cbc -in "$src" -out "$dest" \
		-K "$ENCRYPT_KEY" -iv "$iv" || return 1

	# Note if anyone needs debugging, can be decrypted with:
	# openssl enc -aes-256-cbc -d -in encrypted_file -out decrypted_file -K key -iv iv

	echo "$iv"
}

setup_encryption() {
	[ -z "$ENCRYPT_KEYFILE" ] && return
	[ -e "$ENCRYPT_KEYFILE" ] || \
		error "AES encryption key $ENCRYPT_KEYFILE was set but not found." \
		      "Please create it with genkey.sh --aes \"$ENCRYPT_KEYFILE\""
	ENCRYPT_KEY=$(cat "$ENCRYPT_KEYFILE")
	# XXX if sw-description gets encrypted, its iv is here
	ENCRYPT_KEY="${ENCRYPT_KEY% *}"
}

compress() {
	local file_src="$1"
	local file_out="$2"

	# zstd copies timestamp and test -nt/-ot are strict,
	# "! newer than" is equivalent to "older or equal than"
	[ -e "$file_out" ] && ! [ "$file_src" -nt "$file_out" ] && return

	zstd "$file_src" -o "$file_out.tmp" \
		|| error "failed to compress $file_src"
	mv "$file_out.tmp" "$file_out"
}

write_entry() {
	local file_src="$1"
	local file="${file_src##*/}"
	local file_out="$OUTDIR/$file"
	local compress="$compress"
	shift
	local sha256 arg install_if iv

	[ -e "$file_src" ] || error "Missing source file: $file_src"

	if [ -n "$compress" ]; then
		# Check if already compressed
		case "$file" in
		*.tar.*)
			# archive handler will handle it
			compress=""
			;;
		*.zst)
			compress=zstd
			;;
		*)
			compress=zstd
			file="$file.zst"
			file_out="$file_out.zst"
			compress "$file_src" "$file_out"
			file_src="$file_out"
			;;
		esac
	fi

	if [ -n "$ENCRYPT_KEY" ] && [ -s "$file_src" ]; then
		file="$file.enc"
		file_out="$file_out.enc"
		iv=$(encrypt_file "$file_src" "$file_out") \
			|| error "failed to encrypt $file_src"
		file_src="$file_out"

	fi

	echo "$FILES" | grep -q -x "$file" || FILES="$FILES
$file"

	[ "$file_src" = "$file_out" ] || link "$file_src" "$file_out"

	if [ -e "$file_out.sha256sum" ] && [ "$file_out.sha256sum" -nt "$file_out" ]; then
		sha256=$(cat "$file_out.sha256sum")
	else
		sha256=$(sha256sum < "$file_out") \
			|| error "Checksumming $file_out failed"
		sha256=${sha256%% *}
		echo "$sha256" > "$file_out.sha256sum"
	fi


	write_line "{"
	indent=$((indent+2))
	write_line "filename = \"$file\";"
	if [ -n "$component" ]; then
		case "$component" in
		uboot|kernel)
			install_if="different";;
		extra_os)
			install_if="higher"
			# make sure to reinstall on base os change
			version="$BASE_OS_VERSION.$version";;
		*)
			install_if="higher";;
		esac
		write_line "name = \"$component\";"
		[ -n "$version" ] && write_line "version = \"$version\";" \
						"install-if-${install_if} = true;"
	elif [ -n "$version" ]; then
		error "version $version was set without associated component"
	fi
	[ -n "$compress" ] && write_line "compressed = \"$compress\";"
	[ -n "$iv" ] && write_line "encrypted = true;" "ivt = \"$iv\";"
	write_line "sha256 = \"$sha256\";"
	write_line "$@"

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

pad_uboot() {
	local file="${UBOOT##*/}"
	local src="$UBOOT"
	local size

	UBOOT_SIZE=$(numfmt --from=iec "$UBOOT_SIZE")
	UBOOT="$OUTDIR/$file"

	if [ "$src" -ot "$UBOOT" ]; then
		size=$(stat -c "%s" "$UBOOT")
		if [ "$size" -eq "$UBOOT_SIZE" ]; then
			# already up to date
			return
		fi
	fi

	size=$(stat -c "%s" "$src") || error "Cannot stat uboot: $src"
	if [ "$size" -gt "$UBOOT_SIZE" ]; then
		error "UBOOT_SIZE set smaller than uboot actual size"
	fi
	rm -f "$UBOOT"
	cp "$src" "$UBOOT"
	truncate -s "$UBOOT_SIZE" "$UBOOT"
}

write_uboot() {
	[ -n "$UBOOT_SIZE" ] && pad_uboot
	
	if [ -z "$FORCE" ] && [ -n "$UBOOT_VERSION" ]; then
		strings "$UBOOT" | grep -q -w "$UBOOT_VERSION" || \
			error "uboot version $UBOOT_VERSION was set, but string not present in $UBOOT: aborting"
	fi

	component=uboot version=$UBOOT_VERSION \
		write_entry "$UBOOT" "type = \"raw\";" \
			"device = \"/dev/swupdate_ubootdev\";"
}

write_tar() {
	local source="$1"
	local dest="$2"

	write_entry "$source" "type = \"archive\";" \
		"installed-directly = true;" "path = \"/target$dest\";"
}

write_tar_component() {
	local source="$1"
	local dest="$2"

	write_entry_component "$source" "type = \"archive\";" \
		"installed-directly = true;" "path = \"/target$dest\";"
}

write_files() {
	local file="$1"
	local dest="$2"
	local tarfiles="$3"
	local tarfile_src tarfile tarfiles_out
	local update=
	shift 2
	# other args are source files

	[ -e "$OUTDIR/$file.tar" ] || update=1

	for tarfile_src in $tarfiles; do
		tarfile="${tarfile_src##*/}"
		link "$tarfile_src" "$OUTDIR/$tarfile" && update=1
		[ -z "$update" ] && [ "$tarfile_src" -nt "$OUTDIR/$file.tar" ] && update=1
		tarfiles_out="${tarfiles_out+$tarfiles_out
}$tarfile"
	done
	[ -z "$update" ] || tar -chf "$OUTDIR/$file.tar" -C "$OUTDIR" $tarfiles_out \
		|| error "Could not create tar for $file"
	write_tar "$OUTDIR/$file.tar" "$dest"
}

write_exec_component() {
	local file="$1"
	local command="$2"

	write_entry_component "$file" "type = \"exec\";" \
		"installed-directly = true;" "properties: {" \
		"  cmd: \"$command\"" "}"
}

update_scripts_tar() {
	local f update=

	[ -e "$OUTDIR/scripts.tar" ] || update=1
	for f in "$EMBEDDED_SCRIPTS_DIR"/*; do
		if [ "$f" -nt "$OUTDIR/scripts.tar" ]; then
			update=1
			break
		fi
	done
	[ -z "$update" ] && return

	tar -chf "$OUTDIR/scripts.tar" -C "$EMBEDDED_SCRIPTS_DIR" .
}

write_sw_desc() {
	local IFS="
"
	local indent=4
	local component
	local version
	local compress=1
	local file line tmp tmp2

	cat <<EOF
software = {
  version = "0.1.0";
  description = "Firmware for yakushima";
  hardware-compatibility = [ "1.0" ];
EOF

	for line in $DEBUG_SWDESC; do
		indent=2 write_line $line
	done

	indent=2 write_line "" "images: ("

	update_scripts_tar
	write_entry "$OUTDIR/scripts.tar" "type = \"exec\";" \
		"installed-directly = true;" "properties: {" \
		"  cmd: \"sh -c 'rm -rf \${TMPDIR:-/tmp}/scripts; \\
			mkdir \${TMPDIR:-/tmp}/scripts && \\
			cd \${TMPDIR:-/tmp}/scripts && \\
			tar x -vf \$1 && \\
			./$PRE_SCRIPT' -- \"" \
		"}"

	if [ -n "$UBOOT" ]; then
		write_uboot
	fi

	if [ -n "$BASE_OS" ]; then
		component=base_os version=$BASE_OS_VERSION \
			write_tar "$BASE_OS" "/"
	fi

	if [ -n "$BOOT_FILES" ]; then
		component=kernel version=$KERNEL_VERSION \
			write_files boot /boot "$BOOT_FILES"
	fi

	for file in $EXTRA_TARS; do
		write_tar_component "$file" "/"
	done

	indent=2 write_line ");" "files: ("

	for file in $EMBED_CONTAINERS; do
		tmp=${file##*/}
		tmp=${tmp%.tar*}
		write_exec_component "$file" \
			"${TMPDIR:-/tmp}/scripts/podman_update --storage /target/var/app/storage -l"
	done

	for tmp in $PULL_CONTAINERS; do
		tmp2="${tmp##* }"
		file=$(echo -n "${tmp2}" | tr -c '[:alnum:]' '_')
		file="$OUTDIR/container_$file.pull"
		[ -e "$file" ] || > "$file"
		compress= write_exec_component "${tmp% *} $file" \
			"${TMPDIR:-/tmp}/scripts/podman_update --storage /target/var/app/storage \\\"$tmp2\\\" #"
	done

	for tmp in $USB_CONTAINERS; do
		tmp2=${tmp##*/}
		tmp2=${tmp2%.tar*}
		file="$tmp2.tar"
		link "${tmp##* }" "$OUTDIR/$file"
		sign "$file"
		echo "Copy $OUTDIR/$file and $file.sig to USB drive" >&2
		file="$OUTDIR/container_$tmp2.usb"
		[ -e "$file" ] || > "$file"
		compress= write_exec_component "${tmp% *} $file" \
			"${TMPDIR:-/tmp}/scripts/podman_update --storage /target/var/app/storage --pubkey /etc/swupdate.pem -l /mnt/$tmp2.tar #"
	done

	indent=2 write_line ");" "scripts: ("

	for script in $EXTRA_SCRIPTS; do
		write_entry_component "$script" "type = \"postinstall\";"
	done

	write_entry "$POST_SCRIPT" "type = \"postinstall\";"

	indent=2 write_line ");"
	indent=0 write_line "};"
}

sign() {
	local file="$OUTDIR/$1"

	[ -e "$file.sig" ] && [ "$file.sig" -nt "$file" ] && return

	openssl dgst -sha256 -sign "$PRIVKEY" \
		-sigopt rsa_padding_mode:pss \
		-sigopt rsa_pss_saltlen:-2 \
		${PRIVKEY_PASS:+-passin $PRIVKEY_PASS} \
		-out "$file.sig.tmp" "$file" \
		|| error "Could not sign $file"

	# Note if anyone needs debugging, can be verified with:
	# openssl dgst -sha256 -verify "$PUBKEY" -sigopt rsa_padding_mode:pss \
	#    -sigopt rsa_pss_saltlen:-2 -signature "$file.sig" "$file"

	mv "$file.sig.tmp" "$file.sig"
}

make_cpio() {
	sign sw-description
	(
		cd $OUTDIR
		echo "$FILES" | cpio -ov -H crc -L
	) > $OUT
}

make_image() {
	mkdir -p "$OUTDIR"
	setup_encryption
	write_sw_desc > "$OUTDIR/sw-description"
	# XXX debian's libconfig is obsolete and does not allow
	# trailing commas at the end of lists (allowed from 1.7.0)
	# probably want to sed these out at some point for compatibility
	make_cpio
}


while [ $# -ge 1 ]; do
	case "$1" in
	"-c"|"--config")
		[ $# -lt 2 ] && error "$1 requires an argument"
		CONFIG="$2"
		[ "${CONFIG#/}" = "$CONFIG" ] && CONFIG="./$CONFIG"
		shift 2
		;;
	"-o"|"--out")
		[ $# -lt 2 ] && error "$1 requires an argument"
		OUT="$2"
		OUTDIR="${OUT%.swu}"
		[ "$OUT" != "$OUTDIR" ] || error "$OUT must end with .swu"
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
