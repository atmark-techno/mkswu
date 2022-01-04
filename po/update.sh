#!/bin/sh


dump_po_strings() {
	local script="$1"

	if head -n 1 "$script" | grep -q bash; then
		bash --dump-po-strings "$script"
	else
		sed -e 's/info "\|error "/$"/' < "$script" \
			| bash --dump-po-strings \
			| sed -e 's@bash:@'"$script"':@'
	fi
}

dedup_messages() {
	awk '/^msgid/ && seen[$0]++ {
		# skip 3 lines, including previous one
		getline
		getline
		prev=""
	}
	{
		if (prev) print prev;
		prev=$0
	}
	END {
		if (prev) print prev
	}'
}

DEST="$1"
shift

{
	printf "%s\n" '# header' \
		'msgid ""' \
		'msgstr ""' \
		'"Content-Type: text/plain; charset=UTF-8"'
	for source; do
		dump_po_strings "$source"
	done
} | dedup_messages > "$DEST"
