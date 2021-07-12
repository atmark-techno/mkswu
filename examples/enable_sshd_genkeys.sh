#!/bin/sh

podman run --rm --net=none --rootfs /target /usr/bin/ssh-keygen -A
