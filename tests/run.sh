#!/bin/bash

set -ex
./tests/examples.sh

. ./tests/common.sh

build_check tests/spaces "file container_docker_io_tag_with_spaces.pull"
