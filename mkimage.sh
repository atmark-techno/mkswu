#!/bin/sh

# SC2039: local is ok for dash and busybox ash
# SC1090: non-constant source directives
# SC2165/SC2167: use same variable for nested loops
# shellcheck disable=SC2039,SC1090,SC2165,SC2167

usage() {
	echo "Usage: $0 [opts] desc [desc...]"
	echo
	echo "Options:"
	echo "  -c, --config <conf>     path to config (default mkimage.conf)"
	echo "  -o, --out <out.swu>     path to output file (default from first desc's name)"
	echo "  --mkconf                generate default config file"
	echo "  desc                    image description file(s), if multiple are given"
	echo "                          then the generated image will merge all the contents"
	echo
	echo "desc file syntax:"
	echo "  descriptions are imperative declarations building an image, the following"
	echo "  commands available (see README for details):"
	echo "  - swdesc_boot <bootfile>"
	echo "  - swdesc_tar <tar_file> [--dest <dest>]"
	echo "  - swdesc_files [--basedir <basedir>] [--dest <dest>] <files>"
	echo "  - swdesc_command '<cmd>'"
	echo "  - swdesc_script <script>"
	echo "  - swdesc_exec <file> '<cmd>' (file is \$1 in command)"
	echo "  - swdesc_embed_container <image_archive>"
	echo "  - swdesc_usb_container <image_archive>"
	echo "  - swdesc_pull_container <image_url>"
	echo
	echo "In most cases --version <component> <version> should be set,"
	echo "<component> must be extra_os.* in order to update rootfs"
}

error() {
	local line
	printf %s "ERROR: " >&2
	printf "%s\n" "$@" >&2
	exit 1
}

write_line() {
	local line
	for line; do
		[ -z "$line" ] && continue
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

	track_used "$dest"

	src=$(readlink -e "$src") || error "Cannot find source file: $1"

	if [ -h "$dest" ]; then
		existing=$(readlink "$dest")
		[ "$src" = "$existing" ] && return
		rm -f "$dest" || error "Could not remove previous link at $dest"
	elif [ -e "$dest" ]; then
		cmp "$src" "$dest" > /dev/null && return
		rm -f "$dest" || error "Could not remove previous file at $dest"
	fi

	# files with hardlinks will mess up the order within the cpio,
	# and thus change the order in which components are installed
	# (e.g. rootfs after post script...)
	# workaround by copying file (reflinks are ok) instead if required
	if [ "$(stat -c %h "$src")" != 1 ]; then
		cp --reflink=auto "$src" "$dest" || error "Could not copy $src to $dest"
	else
		ln -s "$(readlink -e "$src")" "$dest" || error "Could not link $dest to $src"
	fi
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

	printf %s "$iv"
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

	track_used "$file_src"

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
	local install_if="$install_if"
	shift
	local sha256 iv

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
			if [ "$(stat -c "%s" "$file_src")" -lt 128 ]; then
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

	printf %s "$FILES" | grep -q -x "$file" || FILES="$FILES
$file"

	[ "$file_src" = "$file_out" ] && track_used "$file_out" \
		|| link "$file_src" "$file_out"

	track_used "$file_out.sha256sum"

	if [ -e "$file_out.sha256sum" ] && [ "$file_out.sha256sum" -nt "$file_out" ]; then
		sha256=$(cat "$file_out.sha256sum")
	else
		sha256=$(sha256sum < "$file_out") \
			|| error "Checksumming $file_out failed"
		sha256=${sha256%% *}
		printf "%s\n" "$sha256" > "$file_out.sha256sum"
	fi


	write_line "{"
	indent=$((indent+2))
	write_line "filename = \"$file\";"
	if [ -n "$component" ]; then
		[ -n "$version" ] || error "component $component was set with empty version"
		if [ -z "$install_if" ]; then
			case "$component" in
			boot) install_if="different";;
			*) install_if="higher";;
			esac
		fi
		case "$install_if" in
		higher)
			local max
			# handle only x.y.z.t or x.y.z-t
			printf %s "$version" | grep -qE '^[0-9]+(\.[0-9]+)?(\.[0-9]+)?(\.[0-9]*|-[A-Za-z0-9.]+)?$' \
				|| error "Version $version must be x.y.z.t (numbers < 65536 only) or x.y.z-t (x-z numbers only)"
			# ... and check for max values
			if [ "${version%-*}" = "${version}" ]; then
				# only dots, "old style version" valid for 16 bits, but now overflow
				# falls back to semver which is signed int but only for 3 elements
				if printf %s "${version}" | grep -qE '\..*\..*\.'; then
					max=65535
				else
					max=2147483647
				fi
				# base_os must be x.y.z-t format to avoid surprises
				# with semver prerelease field filtering
				[ "$component" = "base_os" ] \
					&& error "base_os version $version must be in x[.y[.z]]-t format"
			else
				# semver, signed int
				max=2147483647
			fi
			printf %s "$version" | tr '.-' '\n' | awk '
				/^[0-9]+$/ && $1 > '$max' {
					print $1 " must be <= '$max'";
					exit(1);
				}
				/[0-9][a-zA-Z]|[a-zA-Z][0-9]/ {
					print "WARNING: " $1 " will be sorted alphabetically";
				}' >&2 || error "version check failed: $version"
			;;
		different) ;;
		*) error "install_if must be higher or different";;
		esac
		[ "${component#* }" = "$component" ] || error "component must not contain spaces ($component)"
		[ "${version#* }" = "$version" ] || error "version must not contain spaces ($component = $version)"
		write_line "name = \"$component\";" \
			   "version = \"$version\";" \
			   "install-if-${install_if} = true;"

		# remember version for scripts
		printf "%s\n" "$component $version $install_if" >> "$OUTDIR/sw-description-versions"
	elif [ -n "$version" ]; then
		error "version $version was set without associated component"
	fi
	if [ -n "$main_version" ]; then
		[ -n "$component" ] && [ -n "$version" ] \
			|| error "use as main version requested but component/version not set?"
		write_line "# MAIN_COMPONENT $component" \
			   "# MAIN_VERSION $version"
	fi
	[ -n "$compress" ] && write_line "compressed = \"$compress\";"
	[ -n "$iv" ] && write_line "encrypted = true;" "ivt = \"$iv\";"
	write_line "installed-directly = true;"
	write_line "sha256 = \"$sha256\";"
	write_line "$@"

	indent=$((indent-2))
	write_line "},"
}

write_entry() {
	local outfile="$OUTDIR/sw-description-$1${board:+-$board}"
	shift

	# Running init here allows .desc files to override key elements
	# before the first swdesc_* statement
	if [ -n "$FIRST_SWDESC_INIT" ]; then
		FIRST_SWDESC_INIT=""
		setup_encryption
		embedded_preinstall_script
	fi

	write_entry_stdout "$@" >> "$outfile"
}

parse_swdesc() {
	local ARG SKIP=0 NOPARSE=""

	# first argument tells us what to parse for
	local CMD="$1"
	shift

	for ARG; do
		shift
		# skip previously used argument
		# using a for loop means we can't shift ahead
		if [ "$SKIP" -gt 0 ]; then
			SKIP=$((SKIP-1))
			continue
		fi
		case "$NOPARSE$ARG" in
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
		"--main-version")
			main_version=1
			SKIP=0
			;;
		"--install-if")
			install_if="$1"
			case "$install_if" in
			higher|different) ;;
			*) error "--install-if must be higher or different";;
			esac
			SKIP=1
			;;
		"--preserve-attributes")
			[ "$CMD" = "tar" ] || [ "$CMD" = "files" ] \
				|| error "$ARG only allowed for swdesc_files and swdesc_tar"
			preserve_attributes=1
			SKIP=0
			;;
		"-d"|"--dest")
			[ $# -lt 1 ] && error "$ARG requires an argument"
			[ "$CMD" = "tar" ] || [ "$CMD" = "files" ] \
				|| error "$ARG only allowed for swdesc_files and swdesc_tar"
			dest="$1"
			SKIP=1
			;;
		"--basedir")
			[ $# -lt 1 ] && error "$ARG requires an argument"
			[ "$CMD" = "files" ] \
				|| error "$ARG only allowed for swdesc_files"
			basedir="$1"
			SKIP=1
			;;
		--)
			# we can't break loop or we would reorder previously seen
			# arguments with the rest: just tell parsing to not parse anymore
			# setting NOPARSE here will make the case always fall to last element
			NOPARSE=1
			;;
		"-"*)
			error "$ARG is not a known swdesc_$CMD argument"
			;;
		*)
			set -- "$@" "$ARG"
			;;
		esac
	done
	case "$CMD" in
	boot)
		[ $# -eq 0 ] && [ -n "$BOOT" ] && return
		[ $# -eq 1 ] || error "Usage: swdesc_boot [options] boot_file"
		BOOT="$1"
		;;
	tar)
		[ $# -eq 0 ] && [ -n "$source" ] && return
		[ $# -eq 1 ] || error "Usage: swdesc_tar [options] file.tar"
		source="$1"
		;;
	files)
		[ $# -eq 0 ] && [ -n "$file" ] && [ -n "$tarfiles_src" ] && return
		[ $# -ge 1 ] || error "Usage: swdesc_files [options] file [files...]"
		tarfiles_src="$(printf "%s\n" "$@")"
		;;
	command)
		[ $# -eq 0 ] && [ -n "$cmd" ] && return
		[ $# -ge 1 ] || error "Usage: swdesc_command [options] cmd [cmd..]"
		cmd=""
		for ARG; do
			cmd="${cmd:+$cmd && }$ARG"
		done
		;;
	script)
		[ $# -eq 0 ] && [ -n "$script" ] && return
		[ $# -eq 1 ] || error "Usage: swdesc_script [options] script"
		script="$1"
		;;
	exec)
		[ $# -eq 0 ] && [ -n "$cmd" ] && [ -n "$file" ] && return
		[ $# -ge 2 ] || error "Usage: swdesc_exec [options] file command"
		file="$1"
		shift
		cmd=""
		for ARG; do
			cmd="${cmd:+$cmd && }$ARG"
		done
		;;
	*container)
		[ $# -eq 0 ] && [ -n "$image" ] && return
		[ $# -eq 1 ] || error "Usage: swdesc_$CMD [options] image"
		image="$1"
		;;
	*)
		error "Unhandled command $CMD"
		;;
	esac
}

pad_boot() {
	local file="${BOOT##*/}"
	local src="$BOOT"
	local size

	BOOT_SIZE=$(numfmt --from=iec "$BOOT_SIZE")
	BOOT="$OUTDIR/$file"

	if [ "$src" -ot "$BOOT" ]; then
		size=$(stat -c "%s" "$BOOT")
		if [ "$size" -eq "$BOOT_SIZE" ]; then
			# already up to date
			return
		fi
	fi

	size=$(stat -c "%s" "$src") || error "Cannot stat boot file: $src"
	if [ "$size" -gt "$BOOT_SIZE" ]; then
		error "BOOT_SIZE set smaller than boot file actual size"
	fi
	rm -f "$BOOT"
	cp "$src" "$BOOT"
	truncate -s "$BOOT_SIZE" "$BOOT"
}

swdesc_boot() {
	local BOOT="$BOOT" component=boot version="$version"
	local board="$board" main_version="$main_version"
	local install_if="$install_if"

	parse_swdesc boot "$@"

	[ -n "$BOOT_SIZE" ] && pad_boot

	[ "$component" = "boot" ] \
		|| error "Version component for swdesc_boot must be set to boot"
	if [ -z "$version" ]; then
		version=$(strings "$BOOT" |
				grep -m1 -oE '20[0-9]{2}.[0-1][0-9]-[0-9a-zA-Z.-]*') \
			|| error "Could not guess boot version in $BOOT"
	fi

	write_entry images "$BOOT" "type = \"raw\";" \
		"device = \"/dev/swupdate_bootdev\";"
}

swdesc_tar() {
	local source="$source" dest="$dest"
	local component="$component" version="$version"
	local board="$board" main_version="$main_version"
	local install_if="$install_if"
	local preserve_attributes="$preserve_attributes"
	local target="/target"

	parse_swdesc tar "$@"

	case "$DEBUG_SWDESC" in
	*DEBUG_SKIP_SCRIPTS*) target="";;
	esac
	case "$component" in
	base_os|extra_os*)
		dest="${dest:-/}"
		if [ "${dest#/}" = "$dest" ]; then
			error "OS update must have an absolute dest (was: $dest)"
		fi
		;;
	*)
		dest="${dest:-/var/app/rollback/volumes}"
		case "$dest" in
		/var/app/rollback/volumes*|/var/app/volumes*)
			# ok
			;;
		/*)
			[ -n "$target" ] \
				&& error "OS is only writable for base/extra_os updates and dest ($dest) is not within volumes"
			;;
		..*|*/../*|*/..)
			error ".. is not allowed in destination path for os"
			;;
		*)
			dest="/var/app/rollback/volumes/$dest"
			;;
		esac
	esac

	# it doesn't make sense to not set preserve_attributes
	# for base_os updates: fix it
	if [ "$component" = "base_os" ] \
	    && [ -z "$preserve_attributes" ]; then
		echo "Warning: automatically setting --preserve-attributes for base_os update" >&2
		preserve_attributes=1
	fi
	write_entry images "$source" "type = \"archive\";" \
		"path = \"$target$dest\";" \
		"properties: { create-destination = \"true\"; };" \
		"${preserve_attributes:+preserve-attributes = true;}"
}

set_file_from_content() {
	local content="$*"

	file="$(printf %s "$content" | tr -c '[:alnum:]' '_')"
	if [ "${#file}" -gt 40 ]; then
		file="$(printf %s "$file" | head -c 20)..$(printf %s "$file" | tail -c 20)"
	fi
	file="${file}_$(printf %s "$content" | sha1sum | cut -d' ' -f1)"
	file="$OUTDIR/${file}"
}

swdesc_files() {
	local file="$file" dest="$dest" basedir="$basedir"
	local component="$component" version="$version"
	local board="$board" main_version="$main_version"
	local install_if="$install_if"
	local preserve_attributes="$preserve_attributes"
	local tarfile tarfile_raw tarfiles_src="$tarfiles_src"
	local mtime=0
	local IFS="
"
	parse_swdesc files "$@"

	set -- $tarfiles_src
	# XXX temporary warning -- until when?
	[ -e "$1" ] || error "$1 does not exist" \
		"please note swdesc_files syntax changed and no longer requires setting a name"
	if [ -z "$basedir" ]; then
		[ -d "$1" ] && basedir="$1" || basedir=$(dirname "$1")
	fi

	set --
	for tarfile_raw in $tarfiles_src; do
		tarfile=$(realpath -e -s --relative-to="$basedir" "$tarfile_raw") \
			|| error "$tarfile_raw does not exist?"
		[ "${tarfile#../}" = "$tarfile" ] \
			|| error "$tarfile_raw is not inside $basedir"

		mtime=$({ printf "%s\n" "$mtime"; find "$tarfile_raw" -exec stat -c "%Y" {} +; } \
				| awk '$1 > max { max=$1 } END { print max }')
		set -- "$@" "$tarfile"
	done

	set_file_from_content "$basedir" "$dest" "$@"
	file="$file.tar"

	if ! [ -e "$file" ] \
	    || [ "$mtime" -gt "$(stat -c "%Y" "$file")" ]; then
		tar -cf "$file" -C "$basedir" "$@" \
			|| error "Could not create tar for $file"
	fi

	swdesc_tar "$file"
}


shell_quote() {
	# sh-compliant quote function from http://www.etalabs.net/sh_tricks.html
	printf %s "$1" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/"
}
conf_quote() {
	# Double backslashes, escape double-quotes, replace newlines by \n
	# (the last operation requires reading all input into patternspace first)
	printf %s "$1" | sed  ':a;$!N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\n/\\n/g'
}

swdesc_exec_nochroot() {
	local file="$file" cmd="$cmd"
	local component="$component" version="$version"
	local board="$board" main_version="$main_version"
	local install_if="$install_if"

	parse_swdesc exec "$@"

	[ ! -s "$file" ] || [ "$cmd" != "${cmd#*\$1}" ] \
		|| error 'Using swdesc_exec_nochroot with a non-empty file, but not referring to it with $1'

	cmd="sh -c $(shell_quote "$cmd") --"

	write_entry files "$file" "type = \"exec\";" \
		"properties: {" \
		"  cmd: \"$(conf_quote "$cmd")\"" "}"
}

swdesc_exec() {
	local file="$file" cmd="$cmd" chroot_cmd
	local component="$component" version="$version"
	local board="$board" main_version="$main_version"
	local install_if="$install_if"

	parse_swdesc exec "$@"

	[ ! -s "$file" ] || [ "$cmd" != "${cmd#*\$1}" ] \
		|| error 'Using swdesc_exec with a non-empty file, but not referring to it with $1'

	case "$component" in
	base_os|extra_os*)
		chroot_cmd="podman run --rm --rootfs /target sh -c $(shell_quote "$cmd") -- "
		;;
	*)
		# If target is read-only we need special handling to run (silly podman tries
		# to write to / otherwise) but keep volumes writable
		chroot_cmd="podman run --rm --read-only -v /target/var/app/volumes:/var/app/volumes"
		chroot_cmd="$chroot_cmd -v /target/var/app/rollback/volumes:/var/app/rollback/volumes"
		chroot_cmd="$chroot_cmd --rootfs /target sh -c $(shell_quote "$cmd") -- "
		;;
	esac

	write_entry files "$file" "type = \"exec\";" \
		"properties: {" \
		"  cmd: \"$(conf_quote "$chroot_cmd")\"" "}"
}

swdesc_command() {
	local cmd="$cmd" file
	local component="$component" version="$version"
	local board="$board" main_version="$main_version"
	local install_if="$install_if"

	parse_swdesc command "$@"

	set_file_from_content "$cmd"
	[ -e "$file" ] || : > "$file"

	swdesc_exec
}

swdesc_command_nochroot() {
	local cmd="$cmd" file
	local component="$component" version="$version"
	local board="$board" main_version="$main_version"
	local install_if="$install_if"

	parse_swdesc command "$@"

	set_file_from_content "$cmd"
	[ -e "$file" ] || : > "$file"

	swdesc_exec_nochroot
}

swdesc_script() {
	local script="$script"
	local component="$component" version="$version"
	local board="$board" main_version="$main_version"
	local install_if="$install_if"

	parse_swdesc script "$@"

	swdesc_exec "$script" 'sh $1'
}

swdesc_script_nochroot() {
	local script="$script"
	local component="$component" version="$version"
	local board="$board" main_version="$main_version"
	local install_if="$install_if"

	parse_swdesc script "$@"

	swdesc_exec_nochroot "$script" 'sh $1'
}


swdesc_embed_container() {
	local image="$image"
	local component="$component" version="$version"
	local board="$board" main_version="$main_version"
	local install_if="$install_if"

	parse_swdesc embed_container "$@"

	swdesc_exec_nochroot "$image" '${TMPDIR:-/var/tmp}/scripts/podman_update --storage /target/var/lib/containers/storage_readonly -l $1'
}

swdesc_pull_container() {
	local image="$image"
	local component="$component" version="$version"
	local board="$board" main_version="$main_version"
	local install_if="$install_if"

	parse_swdesc pull_container "$@"

	swdesc_command_nochroot '${TMPDIR:-/var/tmp}/scripts/podman_update --storage /target/var/lib/containers/storage_readonly "'"$image"'"'
}

swdesc_usb_container() {
	local image="$image"
	local component="$component" version="$version"
	local board="$board" main_version="$main_version"
	local install_if="$install_if"

	parse_swdesc usb_container "$@"

	local image_usb=${image##*/}
	if [ "${image_usb%.tar.*}" != "$image_usb" ]; then
		echo "Warning: podman does not handle compressed container images without an extra uncompressed copy"
		echo "you might want to keep the archive as simple .tar"
	fi
	link "$image" "$OUTDIR/$image_usb"
	sign "$image_usb"
	COPY_USB="${COPY_USB:+$COPY_USB }$(shell_quote "$(realpath "$image")")"
	COPY_USB="$COPY_USB $(shell_quote "$(realpath "$OUTDIR/$image_usb.sig")")"

	swdesc_command_nochroot '${TMPDIR:-/var/tmp}/scripts/podman_update --storage /target/var/lib/containers/storage_readonly --pubkey /etc/swupdate.pem -l '"/mnt/$image_usb"
}

embedded_preinstall_script() {
	local f update=""
	local component="" version="" board="" main_version="" install_if=""

	[ -e "$OUTDIR/scripts.tar" ] || update=1
	for f in "$EMBEDDED_SCRIPTS_DIR"/*; do
		if [ "$f" -nt "$OUTDIR/scripts.tar" ]; then
			update=1
			break
		fi
	done
	if [ -n "$update" ]; then
		tar -cf "$OUTDIR/scripts.tar" -C "$EMBEDDED_SCRIPTS_DIR" . \
			|| error "Could not create script.tar"
	fi


	swdesc_exec_nochroot "$OUTDIR/scripts.tar" 'rm -rf ${TMPDIR:-/var/tmp}/scripts' \
			'mkdir ${TMPDIR:-/var/tmp}/scripts' \
			'cd ${TMPDIR:-/var/tmp}/scripts' \
			'tar x -vf $1' "./$PRE_SCRIPT"
}

embedded_postinstall_script() {
	local component="" version="" board="" main_version="" install_if=""
	swdesc_script_nochroot "$POST_SCRIPT"
}

write_sw_desc() {
	local indent=4
	local file line section board=""
	local board_hwcompat board_normalize
	local IFS="
"

	track_used "$OUTDIR/sw-description"

	[ -n "$DESCRIPTION" ] || error "DESCRIPTION must be set"
	cat <<EOF
software = {
  version = "0.1.0";
  description = "$DESCRIPTION";
EOF

	# handle boards files first
	for file in "$OUTDIR/sw-description-"*-*; do
		[ -e "$file" ] || break
		track_used "$file"
		board="${file#*sw-description-*-}"
		[ -e "$OUTDIR/sw-description-done-$board" ] && continue
		touch "$OUTDIR/sw-description-done-$board"
		board_normalize=$(printf %s "$board" | tr -c '[:alnum:]' '_')
		board_hwcompat=$(eval "printf %s \"\$HW_COMPAT_$board_normalize"\")
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
		track_used "$file"
		indent=2 write_line "" "$section: ("
		indent=4 reindent "$OUTDIR/sw-description-$section"
		indent=2 write_line ");"
	done

	# Store highest versions in special comments
	if [ -e "$OUTDIR/sw-description-versions" ]; then
		track_used "$OUTDIR/sw-description-versions"
		sort -Vr < "$OUTDIR/sw-description-versions" | sort -u -k 1,1 | \
			sed -e 's/^/  #VERSION /'
	elif [ -z "$FORCE_VERSION" ]; then
		error "No versions found: empty image?" \
		      "Set FORCE_VERSION=1 to allow building"
	fi
	[ -n "$FORCE_VERSION" ] && echo "  #FORCE_VERSION"
	[ -n "$CONTAINER_CLEAR" ] && echo "  #CONTAINER_CLEAR"
	case "$POST_ACTION" in
	poweroff) echo " #POSTACT_POWEROFF";;
	wait) echo " #POSTACT_WAIT";;
	container) echo " #POSTACT_CONTAINER";;
	""|reboot) ;;
	*) error "invalid POST_ACTION \"$POST_ACTION\", must be empty, poweroff or wait";;
	esac

	# and also add extra debug comments
	for line in $DEBUG_SWDESC; do
		indent=2 write_line "$line"
	done


	indent=0 write_line "};"
}

check_common_mistakes() {
	local swdesc="$OUTDIR/$1"

	# grep for common patterns of easy mistakes that would fail installing
	! grep -qF '$6$salt$hash' "$swdesc" \
		|| error "Please set user passwords (usermod command in .desc)"
}

sign() {
	local file="$OUTDIR/$1"

	track_used "$file.sig"

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
	check_common_mistakes sw-description
	sign sw-description
	(
		cd "$OUTDIR" || error "Could not enter $OUTDIR"
		printf %s "$FILES" | cpio -ov -H crc -L
	) > "$OUT"

	CPIO_FILES=$(cpio -t --quiet < "$OUT")
	[ "$CPIO_FILES" = "$FILES" ] \
		|| error "cpio does not contain files we requested (in the order we requested): check $OUT"
}

track_used() {
	local file

	for file; do
		# only track files inside outdir
		[ "${file#$OUTDIR}" = "$file" ] && continue

		printf "%s\n" "$file" >> "$OUTDIR/used_files"
	done
}

cleanup_outdir() {
	local file

	sort < "$OUTDIR/used_files" > "$OUTDIR/used_files.sorted"
	find "$OUTDIR" | sort \
		| join -v 1 - "$OUTDIR/used_files.sorted" \
		| xargs rm -f
}

update_mkimage_conf() {
	local confdir=$(dirname "$CONFIG") confbase=${CONFIG##*/}
	[ "$confbase" != mkimage.conf ] && return

	# subshell to not source multiple versions of same file
	(
		set -e
		sha=$(sha256sum "$confdir/mkimage.conf.defaults")
		sha=${sha%% *}
		if [ -e "$CONFIG" ]; then
			. "$CONFIG"
			# config exist + no sha: don't update
			[ -z "$DEFAULTS_MKIMAGE_CONF_SHA256" ] && exit
			# sha didn't change: don't update
			[ "$DEFAULTS_MKIMAGE_CONF_SHA256" = "$sha" ] && exit

			# keep old version
			cp "$CONFIG" "$CONFIG.autosave-$(date +%Y%m%d)"

			# update hash, trim comments/empty lines past auto section comment
			sed -e "s/^\(DEFAULTS_MKIMAGE_CONF_SHA256=\).*/\1\"$sha\"/" \
			    -e '/^## auto section/p' -e '/^## auto section/,$ {/^#\|^$/ d}' \
			    "$CONFIG" > "$CONFIG.new"
		else
			cat > "$CONFIG.new" <<EOF
# defaults section: if you remove this include you must keep this file up
# to date with mkimage.conf.defaults changes!
. "\$SCRIPT_DIR/mkimage.conf.defaults"
DEFAULTS_MKIMAGE_CONF_SHA256="$sha"

## user section: this won't be touched

## auto section: you can make changes here but comments will be lost
EOF
		fi
		sed -e 's/^[^#$]/#&/' "$confdir/mkimage.conf.defaults" >> "$CONFIG.new"
		mv "$CONFIG.new" "$CONFIG"

	) || error "Could not update default config"
}

absolutize_file_paths() {
	[ "${PRIVKEY#/}" != "$PRIVKEY" ] || PRIVKEY=$(realpath "$PRIVKEY")
	[ "${PUBKEY#/}" != "$PUBKEY" ] || PUBKEY=$(realpath "$PUBKEY")
	[ -z "$ENCRYPT_KEYFILE" ] \
		|| [ "${ENCRYPT_KEYFILE#/}" != "$ENCRYPT_KEYFILE" ] \
		|| ENCRYPT_KEYFILE=$(realpath "$ENCRYPT_KEYFILE")
}

mkimage() {
	local SCRIPT_DIR
	SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)" || error "Could not get script dir"
	local OUT=""
	local OUTDIR=""
	local CONFIG="$SCRIPT_DIR/mkimage.conf"
	local EMBEDDED_SCRIPTS_DIR="$SCRIPT_DIR/scripts"
	local PRE_SCRIPT="swupdate_pre.sh"
	local POST_SCRIPT="$SCRIPT_DIR/swupdate_post.sh"
	local FILES="sw-description
sw-description.sig"
	local FIRST_SWDESC_INIT=1
	local COPY_USB=""

	# default default values
	local BOOT_SIZE="4M"
	local compress=1
	local main_cwd desc
	local component version board dest

	set -e

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
			[ "${OUT%.swu}" != "$OUT" ] || error "$OUT must end with .swu"
			SKIP=1
			;;
		"--mkconf")
			update_mkimage_conf
			exit 0
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

	if [ -z "$OUT" ]; then
		# OUT defaults to first swu name if not set
		OUT="${1%.desc}.swu"
	fi

	if [ -n "$CONFIG" ]; then
		update_mkimage_conf
		[ -e "$CONFIG" ] || error "$CONFIG does not exist"
		[ "${CONFIG#/}" = "$CONFIG" ] && CONFIG="./$CONFIG"
		. "$CONFIG"
	fi


	# actual image building
	OUTDIR=$(dirname "$OUT")/.$(basename "$OUT" .swu)
	mkdir -p "$OUTDIR"
	OUTDIR=$(realpath "$OUTDIR")
	rm -f "$OUTDIR/sw-description-"* "$OUTDIR/used_files"
	track_used "$OUTDIR"

	main_cwd=$PWD
	absolutize_file_paths
	# build sw-desc fragments
	for desc; do
		[ -e "$desc" ] || error "$desc does not exist"
		cd "$(dirname "$desc")" || error "cannot enter $desc directory"
		. "./${desc##*/}"
		# make key files path absolute after each iteration:
		# this is required if a desc file sets a key path
		absolutize_file_paths
		cd "$main_cwd" || error "Cannot return to $main_cwd we were in before"
	done

	[ -z "$FIRST_SWDESC_INIT" ] || [ -n "$FORCE_VERSION" ] \
		|| error "No or empty desc given?"

	embedded_postinstall_script
	write_sw_desc > "$OUTDIR/sw-description"
	# XXX debian's libconfig is obsolete and does not allow
	# trailing commas at the end of lists (allowed from 1.7.0)
	# probably want to sed these out at some point for compatibility
	# (Note this is only required to run swupdate on debian,
	#  not for image generation)
	make_cpio

	if [ -n "$COPY_USB" ]; then
		echo "----------------"
		echo "You have sideloaded containers, copy all these files to USB drive:"
		echo "$(shell_quote "$(realpath "$OUT")") $COPY_USB"
	fi

	cleanup_outdir

	echo "Successfully generated $OUT"
}


# check if sourced: basename $0 should only be mkimage.sh if run directly
[ "$(basename "$0")" = "mkimage.sh" ] || return

mkimage "$@"
