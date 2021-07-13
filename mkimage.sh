#!/bin/sh

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
OUT=out.swu
OUTDIR=out
CONFIG="$SCRIPT_DIR/mkimage.conf"
EMBEDDED_SCRIPTS_DIR="$SCRIPT_DIR/scripts"
PRE_SCRIPT="swupdate_pre.sh"
POST_SCRIPT="$SCRIPT_DIR/swupdate_post.sh"
FILES="sw-description
sw-description.sig
scripts.tar.zst"

# default default values
UBOOT_SIZE="4M"

usage() {
	echo "Usage: $0 [opts] desc [desc...]"
	echo
	echo "Options:"
	echo "  -c, --config  path to config e.g. mkimage.conf"
	echo "  -o, --out     out.swu"
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
		printf "%*s%s\n" "$((0${line:+1}?indent:0))" "" "$line"
	done
}

reindent() {
	local padding
	padding=$(printf "%*s" "${indent:-0}" "")

	sed -e "s/^/$padding/" "$@"
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

	zstd -10 "$file_src" -o "$file_out.tmp" \
		|| error "failed to compress $file_src"
	mv "$file_out.tmp" "$file_out"
}

write_entry() {
	local file_src="$1"
	local file="${file_src##*/}"
	local file_out="$OUTDIR/$file"
	local compress="$compress"
	shift
	local sha256 install_if iv

	[ -e "$file_src" ] || error "Missing source file: $file_src"

	if [ -n "$compress" ]; then
		# Check if already compressed
		case "$file" in
		*.tar.*|*.apk)
			# archive handler will handle tar, apk already compressed
			compress=""
			;;
		*.zst)
			compress=zstd
			;;
		*)
			# do not compress files < 128 bytes
			if [ $(stat -c "%s" "$file_src") -lt 128 ]; then
				compress=""
			else
				compress=zstd
				file="$file.zst"
				file_out="$file_out.zst"
				compress "$file_src" "$file_out"
				file_src="$file_out"
			fi
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

		# remember version for scripts
		echo "$component $version" >> "$OUTDIR/sw-description-versions"
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

swdesc_uboot() {
	local UBOOT="$1"
	local UBOOT_VERSION="$2"

	[ -n "$UBOOT_SIZE" ] && pad_uboot
	
	if [ -n "$UBOOT_VERSION" ]; then
		strings "$UBOOT" | grep -q -w "$UBOOT_VERSION" || \
			error "uboot version $UBOOT_VERSION was set, but string not present in $UBOOT: aborting"
	else
		UBOOT_VERSION=$(strings "$UBOOT" |
				grep -m1 -oE '20[0-9]{2}.[0-1][0-9]-([0-9]*-)?g[0-9a-f]*')
		[ -n "$UBOOT_VERSION" ] || \
			error "Could not guess uboot version in $UBOOT"
	fi

	component=uboot version=$UBOOT_VERSION \
		write_entry "$UBOOT" "type = \"raw\";" \
			"device = \"/dev/swupdate_ubootdev\";" \
			>> "$OUTDIR/sw-description-images"
}

swdesc_tar() {
	local source="$1"
	local component="$2"
	local version="$3"
	local dest="$4"

	case "$component" in
	base_os|extra_os|kernel)
		dest=${dest:-/}
		;;
	*)
		dest=${dest:-/var/app/volumes}
		[ "${dest#/var/app/volumes}" != "$dest" ] \
			|| error "OS is only writable for base/extra_os updates and $dest is not within volumes"
	esac

	write_entry "$source" "type = \"archive\";" \
		"installed-directly = true;" "path = \"/target$dest\";" \
		>> "$OUTDIR/sw-description-images"
}

swdesc_files() {
	local file="$1"
	local component="$2"
	local version="$3"
	local dest="$4"
	local tarfile_src tarfile
	local update=
	shift 4
	# other args are source files

	[ -e "$OUTDIR/$file.tar" ] || update=1

	for tarfile_src; do
		tarfile="${tarfile_src##*/}"
		link "$tarfile_src" "$OUTDIR/$tarfile" && update=1
		[ -z "$update" ] && [ "$tarfile_src" -nt "$OUTDIR/$file.tar" ] && update=1
		shift
		set -- "$@" "$tarfile"
	done
	[ -z "$update" ] || tar -chf "$OUTDIR/$file.tar" -C "$OUTDIR" "$@" \
		|| error "Could not create tar for $file"
	swdesc_tar "$OUTDIR/$file.tar" "$component" "$version" "$dest"
}

swdesc_script() {
	local script="$1"
	local component="$2"
	local version="$3"

	write_entry "$script" "type = \"postinstall\";" \
		>> "$OUTDIR/sw-description-scripts"
}

swdesc_exec() {
	local file="$1"
	local command="$2"
	local component="$3"
	local version="$4"

	[ -n "$command" ] || error "exec $file has no command"

	write_entry "$file" "type = \"exec\";" \
		"installed-directly = true;" "properties: {" \
		"  cmd: \"$command\"" "}" \
		>> "$OUTDIR/sw-description-files"
}

swdesc_embed_container() {
	local image="$1"
	local component="$2"
	local version="$3"

	# XXX force compression to go through swupdate

	swdesc_exec "$image" "${TMPDIR:-/var/tmp}/scripts/podman_update --storage /target/var/app/storage -l" "$component" "$version"
}

swdesc_pull_container() {
	local image="$1"
	local component="$2"
	local version="$3"

	local image_file=$(echo -n "$image" | tr -c '[:alnum:]' '_')
	image_file="$OUTDIR/container_$image_file.pull"
	[ -e "$image_file" ] || : > "$image_file"

	swdesc_exec "$image_file" "${TMPDIR:-/var/tmp}/scripts/podman_update --storage /target/var/app/storage \\\"$image\\\" #" "$component" "$version"
}

swdesc_usb_container() {
	local image="$1"
	local component="$2"
	local version="$3"

	# XXX test compressed images are handled correctly
	local image_usb=${image##*/}
	image_usb="${image_usb%.tar*}.tar"
	link "$image" "$OUTDIR/$image_usb"
	sign "$image_usb"
	echo "Copy $OUTDIR/$image_usb and $image_usb.sig to USB drive" >&2

	local image_file="$OUTDIR/container_${image_usb%.tar}.usb"
	[ -e "$image_file" ] || : > "$image_file"
	swdesc_exec "$image_file" "${TMPDIR:-/var/tmp}/scripts/podman_update --storage /target/var/app/storage --pubkey /etc/swupdate.pem -l /mnt/$image_usb #" "$component" "$version"
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
	local file line tmp tmp2

	[ -n "$HW_COMPAT" ] || error "HW_COMPAT must be set"
	cat <<EOF
software = {
  version = "0.1.0";
  description = "Firmware for yakushima";
  hardware-compatibility = [ "$HW_COMPAT" ];
EOF

	for line in $DEBUG_SWDESC; do
		indent=2 write_line "$line"
	done

	indent=2 write_line "" "images: ("

	update_scripts_tar
	write_entry "$OUTDIR/scripts.tar" "type = \"exec\";" \
		"installed-directly = true;" "properties: {" \
		"  cmd: \"sh -c 'rm -rf \${TMPDIR:-/var/tmp}/scripts; \\
			mkdir \${TMPDIR:-/var/tmp}/scripts && \\
			cd \${TMPDIR:-/var/tmp}/scripts && \\
			tar x -vf \$1 && \\
			./$PRE_SCRIPT' -- \"" \
		"}"

	[ -e "$OUTDIR/sw-description-images" ] && \
		reindent "$OUTDIR/sw-description-images"

	if [ -e "$OUTDIR/sw-description-files" ]; then
		indent=2 write_line ");" "files: ("
		reindent "$OUTDIR/sw-description-files"
	fi

	indent=2 write_line ");" "scripts: ("

	[ -e "$OUTDIR/sw-description-scripts" ] && \
		reindent "$OUTDIR/sw-description-scripts"

	write_entry "$POST_SCRIPT" "type = \"postinstall\";"

	indent=2 write_line ");"

	# Keep only highest
	sort -Vr < "$OUTDIR/sw-description-versions" | sort -u -k 1,1 | \
		sed -e 's/^/  #VERSION /'

	indent=0 write_line "};"
}

sign() {
	local file="$OUTDIR/$1"

	[ -e "$file.sig" ] && [ "$file.sig" -nt "$file" ] && return
	[ -n "$PRIVKEY" ] || error "PRIVKEY must be set"
	[ -n "$PUBKEY" ] || error "PUBKEY must be set"
	[ -r "$PRIVKEY" ] || error "Cannot read PRIVKEY: $PRIVKEY"
	[ -r "$PUBKEY" ] || error "Cannot read PUBKEY: $PUBKEY"

	openssl cms -sign -in "$file" -out "$file.sig.tmp" \
		-signer "$PUBKEY" -inkey "$PRIVKEY" \
		-outform DER -nosmimecap -binary \
		${PRIVKEY_PASS:+-passin $PRIVKEY_PASS} \
		|| error "Could not sign $file"

	# Note if anyone needs debugging, can be verified with:
	# openssl cms -verify -inform DER -in "$file.sig" -content "$file" \
	#     -nosmimecap -binary -CAfile "$PUBKEY" > /dev/null

	mv "$file.sig.tmp" "$file.sig"
}

make_cpio() {
	sign sw-description
	(
		cd "$OUTDIR" || error "Could not enter $OUTDIR"
		echo "$FILES" | cpio -ov -H crc -L
	) > $OUT
}

make_image() {
	local compress=1

	mkdir -p "$OUTDIR"
	setup_encryption

	# clean and build sw-desc fragments
	rm -f "$OUTDIR/sw-description-"*
	for DESC; do
		[ -e "$DESC" ] || error "$DESC does not exist"
		[ "${DESC#/}" = "$DESC" ] && DESC="./$DESC"
		. "$DESC"
	done

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

if [ -n "$CONFIG" ]; then
	[ -e "$CONFIG" ] || error "$CONFIG does not exist"
	[ "${CONFIG#/}" = "$CONFIG" ] && CONFIG="./$CONFIG"
	. "$CONFIG"
fi

make_image "$@"
