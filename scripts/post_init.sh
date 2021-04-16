init() {
	if [ -e "$SCRIPTSDIR/nothing_to_do" ]; then
		rm -f "$SCRIPTSDIR/nothing_to_do"
		exit 0
	fi

	mmcblk="$(cat "$SCRIPTSDIR/mmcblk")" \
		|| error "Could not read mmcblk from prepare step?!"
	ab="$(cat "$SCRIPTSDIR/ab")" \
		|| error "Could not read ab from prepare step?!"

	if [ -e "$SCRIPTSDIR/needs_reboot" ]; then
		needs_reboot=1
	fi
}

init
