#!/bin/sh

# minimal wrapper around mkimage.sh --genkey for backwards compatibility
SCRIPT_DIR=$(dirname "$0")

exec "$SCRIPT_DIR/mkimage.sh" --genkey "$@"

