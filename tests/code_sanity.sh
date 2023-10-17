#!/bin/bash

set -ex

cd "$(dirname "$0")"

. ./common.sh

# check script was kept up to date and regen diff
diff -u ../examples/update_preserve_files.sh ../examples/update_overlays.sh \
		| grep -vE '^@@' | tail -n +3 \
	> "update_scripts_diff.diff.tmp"
FAIL=""
cmp -s "update_scripts_diff.diff" "update_scripts_diff.diff.tmp" \
	|| FAIL=1
mv "update_scripts_diff.diff.tmp" "update_scripts_diff.diff"
[ -z "$FAIL" ] || error "update_preserve_files or overlays got modified without keeping in sync, check diff"

# certs are up to date in scripts?
for cert in ../certs/*.pem; do
	# update_swupdate_certificate uses base64 pubkey
	b64=$(openssl x509 -noout -in "$cert" -pubkey | sed -e '/-----/d' | tr -d '\n')
	grep -qF "$b64" ../scripts/post_common.sh || error "$cert missing in scripts/pre_init.sh"
	# fail_atmark_new_container uses hex as key position in file
	# isn't fixed and base64 would change depending on offset.
	# The .sig file is actually ASN1 (DER) format which can be dumped,
	# and this verification is strictly equivalent to checking this
	# command's output (with free offsets):
	# openssl asn1parse -inform der -in "$sig" -dump | grep -B 2 -A 7 :id-ecPublicKey
	hex=$(openssl x509 -noout -in "$cert" -pubkey | sed -e '/-----/d' | base64 -d | xxd -p | tr -d '\n')
	grep -qF "$hex" ../scripts/pre_init.sh || error "$cert missing in scripts/pre_init.sh"

done

# test is ok even if last command failed...
true
