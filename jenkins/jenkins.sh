#!/bin/sh

# driver script so we don't need to modify jenkins everytime tests change
set -ex

# setup
SU=
if [ "$(id -u)" = "0" ]; then
	if command -v apk > /dev/null; then
		apk add swupdate bash coreutils cpio zstd
	fi
	SWUPDATE="${SWUPDATE:-swupdate}"
	if command -v "$SWUPDATE" > /dev/null; then
		if ! [ -e /target/bin/sh ]; then
			mkdir -p /target/bin
			cp /bin/sh /target/bin/sh
			ldd /bin/sh | grep -oE '/[^ ]*' | while read -r dep; do
				dest="/target/$(dirname "$dep")"
				mkdir -p "$dest"
				cp "$dep" "$dest"/
			done
		fi
		mkdir -p /target/var/app/volumes /target/var/app/rollback/volumes /target/tmp
		chmod 1777 /target/tmp
	fi
	if [ -n "$USER_ID" ] && [ -n "$GROUP_ID" ]; then
		addgroup -g "$GROUP_ID" testgroup
		adduser -D -G testgroup -u "$USER_ID" testuser
		touch /etc/hwrevision
		chown testuser: /etc/hwrevision
		SU="su testuser -c"
	fi
fi

$SU ./jenkins/armadillo-x2.sh
$SU ./tests/run.sh
