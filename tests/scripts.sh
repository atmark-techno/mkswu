#!/bin/bash

error() {
	echo "$@"
	exit 1
}

set -e

export TEST_SCRIPTS=1
SWDESC=/dev/null

# test user copy on rootfs
. ./scripts/post_rootfs.sh

echo "passwd copy: test normal, OK copy, no extra user"
for f in passwd shadow group; do
	cp ./tests/scripts/$f ./tests/scripts/$f-target
done
PASSWD=./tests/scripts/passwd
NPASSWD=./tests/scripts/passwd-target
SHADOW=./tests/scripts/shadow-set
NSHADOW=./tests/scripts/shadow-target
GROUP=./tests/scripts/group
NGROUP=./tests/scripts/group-target

( update_shadow; ) || error "Normal copy failed"


echo "passwd copy: test not overriding passwd already set"
sed -i -e 's/root:[^:]*/root:GREPMEFAKE/' ./tests/scripts/shadow-target

( update_shadow; ) || error "copy already set failed"
grep -q GREPMEFAKE ./tests/scripts/shadow-target || error "password was overriden"


echo "passwd copy: test leaving empty passwords fail"
for f in passwd shadow group; do
	cp ./tests/scripts/$f ./tests/scripts/$f-target
done
SHADOW=./tests/scripts/shadow
( update_shadow; ) && error "copy should have failed"


echo "passwd copy: test adding new user"
for f in passwd shadow group; do
	cp ./tests/scripts/$f ./tests/scripts/$f-extrauser
	cp ./tests/scripts/$f ./tests/scripts/$f-target
done
cp ./tests/scripts/shadow-set ./tests/scripts/shadow-extrauser
echo 'newuser:x:1001:' >> ./tests/scripts/group-extrauser
echo 'newuser:$6$KWAyQefP7vuRXJyv$Dry6v157pvQgVA/VVTkMd6gygzooCTG1ogN6XNrGi0BHCZs.MuUSlT5Mal9SoPBP97wtKm63ZlGoErZ/JnTFV0:18908:0:99999:7:::' >> ./tests/scripts/shadow-extrauser
echo 'newuser:x:1001:1001:test user:/home/newuser:/bin/ash' >> ./tests/scripts/passwd-extrauser
PASSWD=./tests/scripts/passwd-extrauser
SHADOW=./tests/scripts/shadow-extrauser
GROUP=./tests/scripts/group-extrauser
( update_shadow; ) || error "copy with newuser failed"
grep -q newuser ./tests/scripts/passwd-target || error "newuser not copied (passwd)"
grep -q newuser ./tests/scripts/shadow-target || error "newuser not copied (shadow)"
grep -q newuser ./tests/scripts/group-target || error "newuser not copied (group)"

echo "passwd copy: test running again with new user already existing"
( update_shadow; ) || error "copy with newuser again failed"


echo "passwd copy: test leaving empty passwords is ok with debug set"
for f in passwd shadow group; do
	cp ./tests/scripts/$f ./tests/scripts/$f-target
done
SHADOW=./tests/scripts/shadow
echo "ALLOW_EMPTY_LOGIN" > ./tests/scripts/swdesc
( SWDESC=./tests/scripts/swdesc update_shadow; ) || error "copy should have failed"

true
