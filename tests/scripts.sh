#!/bin/bash

error() {
	printf "%s\n" "$@"
	exit 1
}

set -e

export TEST_SCRIPTS=1
SWDESC=/dev/null
SCRIPTSDIR=./tests/out/scripts
mkdir -p "$SCRIPTSDIR"

# test user copy on rootfs
. ./scripts/post_rootfs.sh

echo "passwd copy: test normal, OK copy, no extra user"
for f in passwd shadow group; do
	cp ./tests/scripts/$f "$SCRIPTSDIR/$f-target"
done
PASSWD=./tests/scripts/passwd
NPASSWD="$SCRIPTSDIR/passwd-target"
SHADOW=./tests/scripts/shadow-set
NSHADOW="$SCRIPTSDIR/shadow-target"
GROUP=./tests/scripts/group
NGROUP="$SCRIPTSDIR/group-target"

( update_shadow; ) || error "Normal copy failed"


echo "passwd copy: test not overriding passwd already set"
sed -i -e 's/root:[^:]*/root:GREPMEFAKE/' "$SCRIPTSDIR/shadow-target"

( update_shadow; ) || error "copy already set failed"
grep -q GREPMEFAKE "$SCRIPTSDIR/shadow-target" || error "password was overriden"


echo "passwd copy: test leaving empty passwords fail"
for f in passwd shadow group; do
	cp ./tests/scripts/$f "$SCRIPTSDIR/$f-target"
done
SHADOW=./tests/scripts/shadow
( update_shadow; ) && error "copy should have failed"


echo "passwd copy: test adding new user"
for f in passwd shadow group; do
	cp ./tests/scripts/$f "$SCRIPTSDIR/$f-extrauser"
	cp ./tests/scripts/$f "$SCRIPTSDIR/$f-target"
done
cp ./tests/scripts/shadow-set "$SCRIPTSDIR/shadow-extrauser"
echo 'newuser:x:1001:' >> "$SCRIPTSDIR/group-extrauser"
echo 'newuser:$6$KWAyQefP7vuRXJyv$Dry6v157pvQgVA/VVTkMd6gygzooCTG1ogN6XNrGi0BHCZs.MuUSlT5Mal9SoPBP97wtKm63ZlGoErZ/JnTFV0:18908:0:99999:7:::' >> "$SCRIPTSDIR/shadow-extrauser"
echo 'newuser:x:1001:1001:test user:/home/newuser:/bin/ash' >> "$SCRIPTSDIR/passwd-extrauser"
PASSWD="$SCRIPTSDIR/passwd-extrauser"
SHADOW="$SCRIPTSDIR/shadow-extrauser"
GROUP="$SCRIPTSDIR/group-extrauser"
( update_shadow; ) || error "copy with newuser failed"
grep -q newuser "$SCRIPTSDIR/passwd-target" || error "newuser not copied (passwd)"
grep -q newuser "$SCRIPTSDIR/shadow-target" || error "newuser not copied (shadow)"
grep -q newuser "$SCRIPTSDIR/group-target" || error "newuser not copied (group)"

echo "passwd copy: test running again with new user already existing"
( update_shadow; ) || error "copy with newuser again failed"


echo "passwd copy: test leaving empty passwords is ok with debug set"
for f in passwd shadow group; do
	cp ./tests/scripts/$f "$SCRIPTSDIR/$f-target"
done
SHADOW=./tests/scripts/shadow
echo "ALLOW_EMPTY_LOGIN" > "$SCRIPTSDIR/swdesc"
( SWDESC="$SCRIPTSDIR/swdesc" update_shadow; ) \
	|| error "should be no failure with allow empty login"



# test certificates update
SWUPDATE_PEM="$SCRIPTSDIR/swupdate.pem"

echo "swupdate certificate: default setup fails"
cat swupdate-onetime-public.pem > "$SWUPDATE_PEM"
( update_swupdate_certificate; ) && error "certificate update should have failed"

echo "swupdate certificate: default setup with allow OK"
cat swupdate-onetime-public.pem > "$SWUPDATE_PEM"
echo "ALLOW_PUBLIC_CERT" > "$SCRIPTSDIR/swdesc"
( SWDESC="$SCRIPTSDIR/swdesc" update_swupdate_certificate; ) \
	|| error "should be ok with allow public cert"
[[ $(grep -c "BEGIN CERT" "$SWUPDATE_PEM") = "1" ]] \
	|| error "should not have removed public key"

echo "swupdate certificate: test with other key"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp256k1 \
	-keyout "$SCRIPTSDIR/key" -out "$SCRIPTSDIR/pub" -subj "/O=SWUpdate/CN=test" \
	-nodes || error "Could not generate new key"
cat swupdate-onetime-public.pem > "$SWUPDATE_PEM"
cat "$SCRIPTSDIR/pub" >> "$SWUPDATE_PEM"
( update_swupdate_certificate; ) \
	|| error "certificate update should be ok with new key"
[[ $(grep -c "BEGIN CERT" "$SWUPDATE_PEM") = "1" ]] \
	|| error "should have removed public key"

echo "swupdate certificate: test with other key, again"
( update_swupdate_certificate; ) \
	|| error "certificate update should be ok with new key"
[[ $(grep -c "BEGIN CERT" "$SWUPDATE_PEM") = "1" ]] \
	|| error "should have removed public key"


true
