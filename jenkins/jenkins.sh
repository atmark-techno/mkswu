#!/bin/sh

# driver script so we don't need to modify jenkins everytime tests change
set -ex

./jenkins/yakushima-eva.sh
./jenkins/examples.sh
