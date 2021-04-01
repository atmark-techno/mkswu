#!/bin/sh

# XXX todo:
# fix partition tables if nothing present (?)
# check which is currently running system (/proc/cmdline)
# create /dev/swupdate_ubootdev (either loop mount with offset (sdcard) or symlink)
# check versions(!) and decide if OS should be wiped or copied
# mount OS to /target, bind mount app inside /target
# if containers, create snapshots for apps
