#!/bin/sh

# driver script so we don't need to modify jenkins everytime tests change
set -ex

./jenkins/armadillo-x2.sh
./tests/run.sh
