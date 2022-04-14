#!/bin/sh

####
#### This file is exactly update_preserve_files with minimal modifications:
####  - help/default path
####  - comment switch removed (code left intact as noop)
####  - conversion helpers from overlay syntax to multiline file
#### keep it in sync! (check enforced)
####

usage() {
	echo "Usage: $0 [options]"
	echo
	echo "Add or remove overlays from /boot/overlays.txt"
	echo
	echo "Each option acts on following arguments"
	echo "Arguments not starting with - are assumed to be overlays to add or remove"
	echo "Default is to add overlays"
	echo "Modifications are done at the end"
	echo
	echo "Options:"
	echo "   --dry-run: Do not modify anything, print modified content"
	echo "   --add: add lines from now on"
	echo "   --del: delete lines from now on"
	echo "   --del-regex: delete lines matching regex (egrep -x)"
	echo "   --file <file>: set alternate file"
	echo "   --: new options are ignored from there on"
}

error() {
	printf "%s\n" "$@" >&2
	[ -n "$tempfile" ] && rm -f "$tempfile"
	[ -n "$newtempfile" ] && rm -f "$newtempfile"
	exit 1
}

shell_quote() {
        # sh-compliant quote function from http://www.etalabs.net/sh_tricks.html
        printf %s "$1" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/"
}

init_tempfile() {
	tempfile="$(mktemp /tmp/update_overlays.XXXXXX)" \
		|| error "Could not create tempfile"
	if [ -s "$file" ]; then
		local linecount=$(wc -l "$file")
		[ "${linecount%% *}" = 1 ] \
			|| error "$file is not empty but contains more than 1 line: aborting"
		grep -qE "^fdt_overlays=" "$file" \
			|| error "$file is not empty but doesn't start with 'fdt_overlays=': aborting"
		sed -e 's/fdt_overlays=//' -e 's/ /\n/g' "$file" > "$tempfile" \
			|| error "Could not write to tempfile"
	fi
}

do_apply() {
	if [ -n "$tempfile" ]; then
		sed -i -e '1s/^/fdt_overlays=/' -e ':a;N;$!ba;s/\n/ /g' "$tempfile"
		if [ -n "$dryrun" ]; then
			cat "$tempfile"
			rm -f "$tempfile"
		elif ! cmp -s "$tempfile" "$file"; then
			mv "$tempfile" "$file" || error "Could not replace $file"
		else
			rm -f "$tempfile"
		fi
		tempfile=""
	fi
}

do_add() {
	local line="$1"
	[ -n "$tempfile" ] || init_tempfile
	grep -qsFx "$line" "${tempfile:-$file}" && return
	if [ -n "$comment" ]; then
		echo "# $comment" >> "$tempfile" \
			|| error "Could not write to tempfile"
		comment=""
	fi
	echo "$line" >> "$tempfile" \
		|| error "Could not write to tempfile"
}

do_del() {
	local line="$1" newtempfile
	[ -n "$tempfile" ] || init_tempfile
	grep -qsFx "$line" "${tempfile:-$file}" || return
	newtempfile="$(mktemp /tmp/update_preserve_files.XXXXXX)" \
		|| error "Could not create tempfile"
	if [ -n "$delcomment" ]; then
		awk -v delcomment="$delcomment" -v line="$line" \
			'$0 == line { printf("# %s: ", delcomment); }
			 { print; }' "$tempfile" > "$newtempfile" \
			|| error "Could not write to tempfile"
	else
		{ grep -vFx "$line" "$tempfile" || :; } > "$newtempfile" \
			|| error "Could not write to tempfile"
	fi
	[ "$file" != "$tempfile" ] && rm -f "$tempfile"
	tempfile="$newtempfile"
}

do_del_regex() {
	local line="$1" newtempfile
	[ -n "$tempfile" ] || init_tempfile
	grep -qsEx "$line" "${tempfile:-$file}" || return
	newtempfile="$(mktemp /tmp/update_preserve_files.XXXXXX)" \
		|| error "Could not create tempfile"
	if [ -n "$delcomment" ]; then
		awk -v delcomment="$delcomment" -v line="^${line}$" \
			'$0 ~ line { printf("# %s: ", delcomment); }
			 { print; }' "$tempfile" > "$newtempfile" \
			|| error "Could not write to tempfile"
	else
		{ grep -vEx "$line" "$tempfile" || :; } > "$newtempfile" \
			|| error "Could not write to tempfile"
	fi
	[ "$file" != "$tempfile" ] && rm -f "$tempfile"
	tempfile="$newtempfile"
}

main() {
	local mode="add" comment="" delcomment="" file="/etc/swupdate_preserve_files"
	local arg nomorearg="" tempfile="" dryrun=""

	for arg; do
		case "$next" in
		comment)
			comment="$arg"
			delcomment="$arg"
			next=""
			continue
			;;
		file)
			do_apply
			file="$arg"
			next=""
			continue
			;;
		"") ;;
		*) error "Invalid next: $next";;
		esac

		if [ -n "$nomorearg" ]; then
			"do_$mode" "$arg"
			continue
		fi

		case "$arg" in
		"--add")
			mode="add";;
		"--del"|"--delete")
			mode="del";;
		"--del-regex")
			mode="del_regex";;
		"--file")
			next="file";;
		"--dry-run")
			dryrun=1;;
		"--help")
			usage; exit 0;;
		"--")
			nomorearg=1;;
		"-"*)
			error "Invalid argument $arg";;
		*)
			"do_$mode" "$arg";;
		esac
	done
	[ -n "$next" ] && error "--$next requires an argument"
	do_apply
}

main "$@"
