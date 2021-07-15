#!/bin/sh

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
	[ -e "$ENCRYPT_KEYFILE" ] \
		|| error "AES encryption key $ENCRYPT_KEYFILE was set but not found." \
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

write_entry_stdout() {
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
		*.tar.*)
			if [ "$compress" = force ]; then
				# Force decompression through swupdate.
				# Only gzip and zstd are supported
				case "$file" in
				*.gz) compress=zlib;;
				*.zst) compress=zstd;;
				*) compress="";;
				esac
			else
				# archive handle will handle it
				compress=""
			fi
			;;
		*.apk)
			# already compressed
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

write_entry() {
	local outfile="$OUTDIR/sw-description-$1${board:+-$board}"
	shift

	write_entry_stdout "$@" >> "$outfile"
}

parse_swdesc() {
	local ARG SKIP=0

	# first argument tells us what to parse for
	local CMD="$1"
	shift

	for ARG; do
		shift
		# skip previously used argument
		# using a for loop means we can't shit ahead
		if [ "$SKIP" -gt 0 ]; then
			SKIP=$((SKIP-1))
			continue
		fi
		case "$ARG" in
		"-b"|"--board")
			[ $# -lt 1 ] && error "$ARG requires an argument"
			board="$1"
			SKIP=1
			;;
		"-v"|"--version")
			[ $# -lt 2 ] && error "$ARG requires <component> <version> arguments"
			component="$1"
			version="$2"
			SKIP=2
			;;
		"-d"|"--dest")
			[ $# -lt 2 ] && error "$ARG requires <component> <version> arguments"
			[ "$CMD" = "tar" ] || [ "$CMD" = "files" ] \
				|| error "$ARG only allowed for swdesc_files and swdesc_tar"
			dest="$1"
			SKIP=1
			;;
		*)
			set -- "$@" "$ARG"
			;;
		esac
	done
	case "$CMD" in
	uboot)
		[ $# -eq 1 ] || error "Usage: swdesc_uboot [options] uboot_file"
		UBOOT="$1"
		;;
	tar)
		[ $# -eq 1 ] || error "Usage: swdesc_tar [options] file.tar"
		source="$1"
		;;
	files)
		[ $# -gt 1 ] || error "Usage: swdesc_files [options] name file [files...]"
		file="$1"
		shift
		tarfiles_src="$(printf "%s\n" "$@")"
		;;
	script)
		[ $# -eq 1 ] || error "Usage: swdesc_script [options] script"
		script="$1"
		;;
	exec)
		[ $# -eq 2 ] || error "Usage: swdesc_exec [options] file command"
		file="$1"
		cmd="$2"
		;;
	*container)
		[ $# -eq 1 ] || error "Usage: swdesc_$CMD [options] image"
		image="$1"
		;;
	*)
		error "Unhandled command $CMD"
		;;
	esac
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
	local UBOOT component=uboot version board="$board"

	parse_swdesc uboot "$@"

	[ -n "$UBOOT_SIZE" ] && pad_uboot

	if [ -n "$version" ]; then
		strings "$UBOOT" | grep -q -w "$version" \
			|| error "uboot version $version was set, but string not present in $UBOOT: aborting"
	else
		version=$(strings "$UBOOT" |
				grep -m1 -oE '20[0-9]{2}.[0-1][0-9]-([0-9]*-)?g[0-9a-f]*')
		[ -n "$version" ] \
			|| error "Could not guess uboot version in $UBOOT"
	fi

	write_entry images "$UBOOT" "type = \"raw\";" \
		"device = \"/dev/swupdate_ubootdev\";"
}

swdesc_tar() {
	local source dest="$dest"
	local component="$component" version="$version" board="$board"
	local target="/target"

	parse_swdesc tar "$@"

	case "$DEBUG_SWDESC" in
	*DEBUG_SKIP_SCRIPTS*) target="";;
	esac
	case "$component" in
	base_os|extra_os*|kernel)
		dest="${dest:-/}"
		;;
	*)
		dest="${dest:-/var/app/volumes}"
		[ "${dest#/var/app/volumes}" = "$dest" ] \
			&& [ -n "$target" ] \
			&& error "OS is only writable for base/extra_os updates and $dest is not within volumes";;
	esac

	write_entry images "$source" "type = \"archive\";" \
		"installed-directly = true;" "path = \"$target$dest\";"
}

swdesc_files() {
	local file dest="$dest"
	local component="$component" version="$version" board="$board"
	local tarfile_src tarfile tarfiles_src
	local update=
	local IFS="
"

	parse_swdesc files "$@"

	[ -e "$OUTDIR/$file.tar" ] || update=1

	set --
	for tarfile_src in $tarfiles_src; do
		tarfile="${tarfile_src##*/}"
		link "$tarfile_src" "$OUTDIR/$tarfile" && update=1
		[ -z "$update" ] && [ "$tarfile_src" -nt "$OUTDIR/$file.tar" ] && update=1
		set -- "$@" "$tarfile"
	done
	[ -z "$update" ] || tar -chf "$OUTDIR/$file.tar" -C "$OUTDIR" "$@" \
		|| error "Could not create tar for $file"
	swdesc_tar "$OUTDIR/$file.tar"
}

swdesc_script() {
	local script cmd
	local component="$component" version="$version" board="$board"
	local compress=""

	parse_swdesc script "$@"

	case "$component" in
	base_os|extra_os*|kernel)
		cmd="podman run --rm --rootfs /target sh"
		;;
	*)
		# If target is read-only we need special handling to run (silly podman tries
		# to write to / otherwise) but keep volumes writable
		cmd="podman run --rm --read-only -v /target/var/app/volumes:/var/app/volumes"
		cmd="$cmd -v /target/var/app/volumes_persistent:/var/app/volumes_persistent"
		cmd="$cmd --rootfs /target sh"
		;;
	esac
	write_entry files "$script" "type = \"exec\";" \
		"properties: {" "  cmd: \"$cmd\"" "}"
}

swdesc_script_nochroot() {
        local script
	local component="$component" version="$version" board="$board"
	parse_swdesc script "$@"

        write_entry scripts "$script" "type = \"postinstall\";"
}

swdesc_exec() {
	local file cmd
	local component="$component" version="$version" board="$board"
	parse_swdesc exec "$@"

	write_entry files "$file" "type = \"exec\";" \
		"installed-directly = true;" "properties: {" \
		"  cmd: \"$cmd\"" "}"
}

swdesc_embed_container() {
	local image
	local component="$component" version="$version" board="$board"
	local compress="force"
	parse_swdesc embed_container "$@"

	swdesc_exec "$image" "${TMPDIR:-/var/tmp}/scripts/podman_update --storage /target/var/app/storage -l"
}

swdesc_pull_container() {
	local image
	local component="$component" version="$version" board="$board"
	parse_swdesc pull_container "$@"

	local image_file=$(echo -n "$image" | tr -c '[:alnum:]' '_')
	image_file="$OUTDIR/container_$image_file.pull"
	[ -e "$image_file" ] || : > "$image_file"

	swdesc_exec "$image_file" "${TMPDIR:-/var/tmp}/scripts/podman_update --storage /target/var/app/storage \\\"$image\\\" #"
}

swdesc_usb_container() {
	local image
	local component="$component" version="$version" board="$board"
	parse_swdesc usb_container "$@"

	local image_usb=${image##*/}
	if [ "${image_usb%.tar.*}" != "$image_usb" ]; then
		echo "Warning: podman does not handle compressed container images without an extra uncompressed copy"
		echo "you might want to keep the archive as simple .tar"
	fi
	link "$image" "$OUTDIR/$image_usb"
	sign "$image_usb"
	echo "Copy $OUTDIR/$image_usb and $image_usb.sig to USB drive" >&2

	local image_file="$OUTDIR/container_${image_usb%.tar}.usb"
	[ -e "$image_file" ] || : > "$image_file"
	swdesc_exec "$image_file" "${TMPDIR:-/var/tmp}/scripts/podman_update --storage /target/var/app/storage --pubkey /etc/swupdate.pem -l /mnt/$image_usb #"
}

embedded_preinstall_script() {
	local f update=
	local component version board

	[ -e "$OUTDIR/scripts.tar" ] || update=1
	for f in "$EMBEDDED_SCRIPTS_DIR"/*; do
		if [ "$f" -nt "$OUTDIR/scripts.tar" ]; then
			update=1
			break
		fi
	done
	[ -n "$update" ] \
		&& tar -chf "$OUTDIR/scripts.tar" -C "$EMBEDDED_SCRIPTS_DIR" .

	swdesc_exec "$OUTDIR/scripts.tar" "sh -c 'rm -rf \${TMPDIR:-/var/tmp}/scripts; \\
			mkdir \${TMPDIR:-/var/tmp}/scripts && \\
			cd \${TMPDIR:-/var/tmp}/scripts && \\
			tar x -vf \$1 && \\
			./$PRE_SCRIPT' -- "
}

embedded_postinstall_script() {
	local component version board
	swdesc_script_nochroot "$POST_SCRIPT"
}

write_sw_desc() {
	local indent=4
	local file line section board=""
	local board_hwcompat board_normalize
	local IFS="
"

	[ -n "$DESCRIPTION" ] || error "DESCRIPTION must be set"
	cat <<EOF
software = {
  version = "0.1.0";
  description = "$DESCRIPTION";
EOF

	# handle boards files first
	for file in "$OUTDIR/sw-description-"*-*; do
		[ -e "$file" ] || break
		board="${file#*sw-description-*-}"
		[ -e "$OUTDIR/sw-description-done-$board" ] && continue
		touch "$OUTDIR/sw-description-done-$board"
		board_normalize=$(echo -n "$board" | tr -c '[:alnum:]' '_')
		board_hwcompat=$(eval "echo \"\$HW_COMPAT_$board_normalize"\")
		[ -n "$board_hwcompat" ] || board_hwcompat="$HW_COMPAT"
		[ -n "$board_hwcompat" ] || error "HW_COMPAT or HW_COMPAT_$board_normalize must be set"
		indent=2 write_line "$board = {"
		indent=4 write_line "hardware-compatibility = [ \"$board_hwcompat\" ];"
		for file in "$OUTDIR/sw-description-"*"-$board"; do
			[ -s "$file" ] || continue
			section=${file##*sw-description-}
			section=${section%%-*}
			indent=4 write_line "$section: ("
			indent=6 reindent "$file"
			# also need to include common files if any
			[ -e "$OUTDIR/sw-description-$section" ] \
				&& indent=6 reindent "$OUTDIR/sw-description-$section"
			indent=4 write_line ");"
		done
		indent=2 write_line "};"
	done

	# only set global hardware-compatibility if no board specific ones found
	if [ -z "$board" ]; then
		[ -n "$HW_COMPAT" ] || error "HW_COMPAT must be set"
		echo "  hardware-compatibility = [ \"$HW_COMPAT\" ];"
	fi

	for file in "$OUTDIR/sw-description-"*; do
		board="${file##*sw-description-}"
		section="${board%-*}"
		[ "$section" = "$board" ] && board="" || board="${board#*-}"


	done

	# main sections for all boards
	for section in images files scripts; do
		file="$OUTDIR/sw-description-$section"
		[ -e "$file" ] || continue
		indent=2 write_line "" "$section: ("
		indent=4 reindent "$OUTDIR/sw-description-$section"
		indent=2 write_line ");"
	done

	# Store highest versions in special comments
	if [ -e "$OUTDIR/sw-description-versions" ]; then
		sort -Vr < "$OUTDIR/sw-description-versions" | sort -u -k 1,1 | \
			sed -e 's/^/  #VERSION /'
	elif [ -z "$FORCE_VERSION" ]; then
		error "No versions found: empty image?" \
		      "Set FORCE_VERSION=1 to allow building"
	fi
	[ -n "$FORCE_VERSION" ] && echo "  #VERSION_FORCE"

	# and also add extra debug comments
	for line in $DEBUG_SWDESC; do
		indent=2 write_line "$line"
	done


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

mkimage() {
	local SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
	local OUT=out.swu
	local OUTDIR=out
	local CONFIG="$SCRIPT_DIR/mkimage.conf"
	local EMBEDDED_SCRIPTS_DIR="$SCRIPT_DIR/scripts"
	local PRE_SCRIPT="swupdate_pre.sh"
	local POST_SCRIPT="$SCRIPT_DIR/swupdate_post.sh"
	local FILES="sw-description
sw-description.sig"

	# default default values
	local UBOOT_SIZE="4M"
	local compress=1
	local component version board dest


	local ARG SKIP=0
	for ARG; do
		shift
		# skip previously used argument
		# using a for loop means we can't shit ahead
		if [ "$SKIP" -gt 0 ]; then
			SKIP=$((SKIP-1))
			continue
		fi
		case "$ARG" in
		"-c"|"--config")
			[ $# -lt 1 ] && error "$ARG requires an argument"
			CONFIG="$1"
			SKIP=1
			;;
		"-o"|"--out")
			[ $# -lt 1 ] && error "$ARG requires an argument"
			OUT="$1"
			OUTDIR="${OUT%.swu}"
			[ "$OUT" != "$OUTDIR" ] || error "$OUT must end with .swu"
			SKIP=1
			;;
		"-h"|"--help"|"-"*)
			usage
			exit 0
			;;
		*)
			set -- "$@" "$ARG"
			;;
		esac
	done

	if [ -n "$CONFIG" ]; then
		[ -e "$CONFIG" ] || error "$CONFIG does not exist"
		[ "${CONFIG#/}" = "$CONFIG" ] && CONFIG="./$CONFIG"
		. "$CONFIG"
	fi


	# actual image building
	mkdir -p "$OUTDIR"
	rm -f "$OUTDIR/sw-description-"*
	setup_encryption
	embedded_preinstall_script

	# build sw-desc fragments
	for DESC; do
		[ -e "$DESC" ] || error "$DESC does not exist"
		[ "${DESC#/}" = "$DESC" ] && DESC="./$DESC"
		. "$DESC"
	done

	embedded_postinstall_script
	write_sw_desc > "$OUTDIR/sw-description"
	# XXX debian's libconfig is obsolete and does not allow
	# trailing commas at the end of lists (allowed from 1.7.0)
	# probably want to sed these out at some point for compatibility
	make_cpio
}


# check if sourced: basename $0 should only be mkimage.sh if run directly
[ "$(basename "$0")" = "mkimage.sh" ] || return

mkimage "$@"
