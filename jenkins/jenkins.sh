#!/bin/sh

# driver script so we don't need to modify jenkins everytime tests change
set -ex

# setup
SU=eval
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

$SU "./mkswu --config-dir . --mkconf"

$SU ./jenkins/armadillo-x2.sh

# only need to run this once (on debian that has msgmerge),
# we don't care if alpine can't make dist.
if command -v msgmerge >/dev/null; then
	# remove old .pot files to make sure make regenerates all locales
	rm po/*.pot
	make dist
fi

# If we want to build debian package, quite a bit of work...
case "$1" in
deb)
	sudo apt update
	sudo apt install -y debhelper jq pandoc
	VERSION=$(git describe | tr '-' '.')

	rm -rf /tmp/mkswu && mkdir /tmp/mkswu
	GIT_WORK_TREE=/tmp/mkswu git reset --hard HEAD
	cp .version /tmp/mkswu/
	mv "mkswu_$VERSION.orig.tar.xz" /tmp
	cd /tmp/mkswu

	if ! head -n 1 debian/changelog | grep -qF "($VERSION-1)"; then
		# add new entry to debian changelog if we're not clean
		# the normal way of doing that is through dch but devscripts
		# pulls in quite a few deps, so just wade it through...
		cat > debian/newchangelog <<EOF
mkswu ($VERSION-1) experimental; urgency=low

  * jenkins autoupdate, not meant for releasing

 -- jenkins jenkins <no-reply@atmark-techno.com>  $(date -R)

EOF
		cat debian/changelog >> debian/newchangelog
		mv debian/newchangelog debian/changelog
	fi
	dpkg-buildpackage -us -uc

	sudo dpkg -i "../mkswu_${VERSION}-1_all.deb"

	# clean existing user config and retest with package
	rm -rf ~/mkswu
	mkswu --genkey --config-dir . --plain --cn test
	mkswu --import
	rm -f mkswu.conf
	MKSWU=mkswu ./tests/run.sh

	mkdir -p /work/deb
	mv ../mkswu_* /work/deb/
	;;
*)
	$SU ./tests/run.sh
	;;
esac
