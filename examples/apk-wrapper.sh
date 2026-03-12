#!/bin/sh
# SPDX-License-Identifier: MIT

# wrapper to run apk-tool, extracted from https://github.com/alpinelinux/alpine-make-rootfs.git
APK_KEYS='
atmark-601a0e69.rsa.pub:MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsGhwCSao1swqUGNSIPg5cL+Wxs2J2HrHCfi8pfL4l+yTHhmLXA353TFDcgpBTrhfAjjSQVQMa45G+keJlyeg9z7SXVwUzCSI7HZYp3qQ6ljXKqpsxo7rhlOBXY9d6kQ4oRSmQ7eUn9oaspEpIqI7JhsR6kxoC77zLd5BpBrNu/9A2L/oBwmhoVhCJoHSe6+JmSraF4/PJED2c7BUFje7hPFQArvx3N9x+xKgNhG96dehtodi808MD3X8G82668lxIUxt2Qehk1/mE3Kpy/xGZXkZ/SbIXVKKqlL4y8H1QzAPvjqpunIS+vQdwXDu5kMziApJbmDjVJwOQoAds6kghQIDAQAB
atmark-62b116af.rsa.pub:MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAvujbgM/5uNDUtbPSIeK7kZzO/3SyLv+LhbshucdGEKFysKZjYmXwJVuKMWCB6ySzhou+v6y5GixwPVVZR09fGDzZnzkr4fA/D6Ky/qLtENsBKN4p6ce0f/Sui9HEeLS+mtu+2MFTs3i7D/xHgKDNVCCsaETUxpGYaVgYBQ9U2Mg4JFbO2RCFbkvb6psceF94nmXunFxxotQ82mWc22B2bIzcaKEULsR5MO7VRh52WNQOTj8dbirvX6jc2UB44vsa9tQDeOGIbX4aERzxfJDX4xJmUQgZO7tir29oKuBVGDaXMZxWDZ4ogrGPTxvtdXMSiWDKBk4SuTZ6Rp3UzZKWM2qpKzyw26dSldytcAKBhgU6+2LVVG1soV9fyPJ0yyXJGxtkYfQVW4rdD1XL8++Qo5YUUMRxv5xf75ds6HAZ+qZrNTsZSHzvMD/LI4WlgI7x/2uDWEMo9hfX2qG11HsmOJH6NBxKB54M1U/7irJACqwYx0Rbx+ASTxjCW+c9S3th+GdgSC62EHAL4ljzcOx/wPAtC+/OMIoipP1LBBT6EJlawyYYr3+uV+8WLh+ihsCOZ8Me5hg/vkZHwzYmDA1zkk67Ql7U0s/67wY+Iz2BPXN1RB3Vu2HbB5SCHeaWFZYDysxDhb/5WZYU7St4neKTQcHxcibnl4d9nET12H01TQsCAwEAAQ==
'
APK_REPOS='
https://download.atmark-techno.com/alpine/current/atmark
'
: "${APK:=apk}"
: "${CACHE_DIR:="$HOME/.cache/mkswu"}"
: "${APK_ROOT:="$CACHE_DIR/apkroot"}"
: "${APK_TOOLS_URI:="https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v2.14.0/x86_64/apk.static"}"
: "${APK_TOOLS_SHA256:="1c65115a425d049590bec7c729c7fd88357fbb090a6fc8c31d834d7b0bc7d6f2"}"

dump_apk_keys() {
	local dest_dir="$1"
	local content file line

	mkdir -p "$dest_dir"
	for line in $APK_KEYS; do
		file=${line%%:*}
		content=${line#*:}

		printf -- "-----BEGIN PUBLIC KEY-----\n%s\n-----END PUBLIC KEY-----\n" \
			"$content" > "$dest_dir/$file"
	done
}

curl_and_check() (
	local url="$1"
	local sha256="$2"
	local dest="${3:-.}"

	mkdir -p "$dest"
	cd "$dest" \
		&& curl -sSf -O "$url" \
		&& echo "$sha256  ${url##*/}" | sha256sum -c
)

find_or_get_apk() {
	command -v "$APK" >/dev/null && return
	APK="$CACHE_DIR/apk.static"
	command -v "$APK" >/dev/null && return
	echo "$APK not found, downloading static apk-tools"
	curl_and_check "$APK_TOOLS_URI" "$APK_TOOLS_SHA256" "${APK%/*}" || exit
	chmod +x "$APK" || exit
}

main() {
	find_or_get_apk

	if ! stat "$APK_ROOT/var/cache/apk/APKINDEX"* >/dev/null 2>&1; then
		echo "Initializing repo in $APK_ROOT"
		dump_apk_keys "$APK_ROOT/etc/apk/keys"
		echo "$APK_REPOS" > "$APK_ROOT/etc/apk/repositories"
		"$APK" --root "$APK_ROOT" --initdb add
	fi

	"$APK" --root "$APK_ROOT" "$@"
}

main "$@"
