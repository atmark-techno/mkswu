#!/bin/sh

usage() {
	echo "Usage: $0 [options] text [text...]"
	echo
	echo "Add or remove lines from /etc/swupdate_preserve_files"
	echo
	echo "Each option acts on following arguments"
	echo "Arguments not starting with - are assumed to be line to add or remove"
	echo "Default is to add lines"
	echo "Modifications are done at the end (or when selecting a new file)"
	echo
	echo "Options:"
	echo "   --dry-run: Do not modify anything, print modified content"
	echo "   --file <file>: set alternate file"
	echo "   --add: add lines from now on"
	echo "   --del: delete lines from now on"
	echo "   --del-regex: delete lines matching regex (egrep -x)"
	echo "   --comment <comment>: add comment before the next addition or any deletion"
	echo "                        This does not add anything if no line is added,"
	echo "                        Deletions will comment the line being removed with this"
	echo "                        instead of removing the line"
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
	tempfile="$(mktemp /tmp/update_preserve_files.XXXXXX)" \
		|| error "Could not create tempfile"
	if [ -e "$file" ]; then
		cp "$file" "$tempfile" \
			|| error "Could not write to tempfile"
	fi
}

do_apply() {
	if [ -n "$tempfile" ]; then
		if [ -n "$dryrun" ]; then
			cat "$tempfile"
			rm -f "$tempfile"
		else
			mv "$tempfile" "$file" || error "Could not replace $file"
		fi
		tempfile=""
	fi
}

do_add() {
	local line="$1"
	grep -qsFx "$line" "${tempfile:-$file}" && return
	[ -n "$tempfile" ] || init_tempfile
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
	grep -qsFx "$line" "${tempfile:-$file}" || return
	[ -n "$tempfile" ] || tempfile="$file"
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
	grep -qsEx "$line" "${tempfile:-$file}" || return
	[ -n "$tempfile" ] || tempfile="$file"
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
		"--comment")
			next="comment";;
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
