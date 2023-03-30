#!/bin/bash

set -e

cd "$(dirname "$0")/.."

build_check_env() {
	(
		declare -p > tests/out/env_pre
		. "./mkswu"
		mkimage	"$@" || exit
		declare -p > tests/out/env_post
	)
	diff -u tests/out/env_pre tests/out/env_post
}

build_check_env -o tests/out/spaces.swu tests/spaces.desc
