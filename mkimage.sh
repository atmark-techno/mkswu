#!/bin/sh

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
OUT=out.swu
OUTDIR=./out
CONFIG=./mkimage.conf
FILES="sw-description
sw-description.sig"
EMBEDDED_SCRIPT="$SCRIPT_DIR/embedded_script.lua"
EMBEDDED_SCRIPTS_DIR="embedded_scripts"
POST_SCRIPT="$SCRIPT_DIR/swupdate_post.sh"

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
		[ "$src" = "$existing" ] && return
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

	echo "$iv"
}

setup_encryption() {
	local oldumask
	[ -z "$ENCRYPT_KEYFILE" ] && return
	if ! [ -e "$ENCRYPT_KEYFILE" ]; then
		echo "Creating encryption keyfile $ENCRYPT_KEYFILE"
		echo "That file must be copied over to /etc/swupdate.aes-key as 0400 on boards"
		oldumask=$(umask)
		umask 0077
		ENCRYPT_KEY="$(openssl rand -hex 32)" || error "No openssl?"
		echo "$ENCRYPT_KEY $(gen_iv)" > "$ENCRYPT_KEYFILE"
		umask "$oldumask"
	else
		ENCRYPT_KEY=$(cat "$ENCRYPT_KEYFILE")
		# XXX if sw-description gets encrypted, its iv is here
		ENCRYPT_KEY="${ENCRYPT_KEY% *}"
	fi
}

write_entry() {
	local file_src="$1"
	local file="${file_src##*/}"
	local file_out="$OUTDIR/$file"
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
			file_src="$file_out"
			zst "$file_src" > "$file_out".zst \
				|| error "failed to compress $file_src"
			;;
		esac
	fi

	if [ -n "$ENCRYPT_KEY" ] && [ -z "$noencrypt" ]; then
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
		sha256=$(sha256sum < "$file_out")
		sha256=${sha256%% *}
		echo "$sha256" > "$file_out.sha256sum"
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
	case "$component" in
		uboot) write_line "hook = \"uboot_hook\";";;
	esac
	[ -n "$compress" ] && write_line "compressed = \"$compress\";"
	[ -n "$iv" ] && write_line "encrypted = true;" "ivt = \"$iv\";"
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
			error "uboot version $UBOOT_VERSION was set, but string not present in binary: aborting"
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
	shift 2
	# other args are source files

	for tarfile_src in $tarfiles; do
		tarfile="${tarfile_src##*/}"
		link "$tarfile_src" "$OUTDIR/$tarfile"
		tarfiles_out="${tarfiles_out+$tarfiles_out
}$tarfile"
	done
	tar -chf "$OUTDIR/$file.tar" -C "$OUTDIR" $tarfiles_out \
		|| error "Could not create tar for $file"
	write_tar "$OUTDIR/$file.tar" "$dest"
}

write_file_component() {
	local file="$1"
	local dest="$2"

	write_entry_component "$file" "type = \"rawfile\";" \
		"installed-directly = true;" "path = \"/target$dest\";"
}

write_sw_desc() {
	local IFS="
"
	local indent=4
	local component
	local version
	local compress
	local noencrypt
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

	if [ -n "$UBOOT" ]; then
		write_uboot
	fi

	if [ -n "$BASE_OS" ]; then
		component=base_os version=$BASE_OS_VERSION compress=1 \
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
		compress=1 write_file_component "$file" \
			"/var/tmp/podman_update/container_$tmp.tar"
	done

	for tmp in $PULL_CONTAINERS; do
		tmp2="${tmp##* }"
		file=$(echo -n "${tmp2}" | tr -c '[:alnum:]' '_')
		file="$OUTDIR/container_$file.pull"
		[ -e "$file" ] && [ "$(cat "$file")" = "$tmp2" ] \
			|| echo "$tmp2" > "$file"
		noencrypt=1 write_file_component "${tmp% *} $file" \
			"/var/tmp/podman_update/${file##*/}"
	done

	for tmp in $USB_CONTAINERS; do
		tmp2=${tmp##*/}
		tmp2=${tmp2%.tar*}
		file="container_$tmp2.tar"
		link "${tmp##* }" "$OUTDIR/$file"
		sign "$file"
		echo "Copy $OUTDIR/$file $OUTDIR/$file.sig to USB drive" >&2
		file="$OUTDIR/container_$tmp2.usb"
		[ -e "$file" ] || > "$file"
		noencrypt=1 write_file_component "${tmp% *} $file" \
			"/var/tmp/podman_update/${file##*/}"
	done

	indent=2 write_line ");" "scripts: ("

	for script in $EXTRA_SCRIPTS; do
		write_entry_component "$script" "type = \"postinstall\";"
	done

	write_entry "$POST_SCRIPT" "type = \"postinstall\";"

	indent=2 write_line ");" "embedded-script = \""
	sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' < "$EMBEDDED_SCRIPT"

	echo 'archive = \"\'
	tar -C "$(dirname "$EMBEDDED_SCRIPT")" -chJ "$EMBEDDED_SCRIPTS_DIR" \
		| base64 | sed -e 's/$/\\/'
	cat <<EOF
\"
exec_pipe(\"base64 -d | xzcat | tar -C ${TMPDIR:-/tmp} -xv\", archive)
exec(\"${TMPDIR:-/tmp}/$EMBEDDED_SCRIPTS_DIR/swupdate_pre.sh\")
EOF

	indent=2 write_line "\";"
	indent=0 write_line "};"
}

sign() {
	local file="$OUTDIR/$1"

	openssl dgst -sha256 -sign "$PRIVKEY" -sigopt rsa_padding_mode:pss \
		-sigopt rsa_pss_saltlen:-2 "$file" > "$file.sig" \
		|| error "Could not sign $file"
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
