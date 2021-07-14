#!/bin/sh

# driver script so we don't need to modify jenkins everytime tests change
set -ex

./jenkins/yakushima-eva.sh
./jenkins/yakushima-es1.sh
./tests/run.sh
