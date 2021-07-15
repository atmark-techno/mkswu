#!/bin/sh

# driver script so we don't need to modify jenkins everytime tests change
set -ex

./jenkins/yakushima.sh
./tests/run.sh
