#!/bin/bash

set -o pipefail
set -eu 

OUT=${1:-out}.swu

FILES=( sw-description sw-description.sig )

while read file; do
	found=no
	for f in "${FILES[@]}"; do
		if [[ "$file" == "$f" ]]; then
			found=yes
			break;
		fi
	done
	[[ "$found" == "no" ]] || continue
	FILES+=( $file )

	# for disk, check if tar exists and reconvert if required
	if [[ "$file" = *".img.zst" ]]; then
		tar="${file%.img.zst}.tar.gz"
		if [[ -e "$tar" ]] && [[ ! -e "$file" || "$tar" -nt "$file" ]]; then
			echo "Regenerating $file from tar..."
			virt-make-fs --size=500M --format=raw --type=ext4 $tar "${file%.zst}"
			zstd --rm "${file%.zst}"
		fi
	fi

	# skip computing checksum if we generated an image more recently
	[[ -e "$OUT" && "$OUT" -nt "$file" ]] && continue

	echo -n "Computing sha256sum for $file..."
	SHA=$(sha256sum "$file" | cut -d' ' -f1)
	echo " $SHA"

	sed -i -e "/filename = \"$file\"/,/sha256/ s/sha256.*/sha256 = \"${SHA}\";/" sw-description
done < <(sed -ne 's/.*filename = "\(.*\)".*/\1/p' sw-description)


openssl dgst -sha256 -sign priv.pem -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-2 sw-description > sw-description.sig

printf "%s\n" "${FILES[@]}" | cpio -ov -H crc > $OUT
