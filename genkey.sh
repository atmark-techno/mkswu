#!/bin/sh

# minimal wrapper around mkswu --genkey for backwards compatibility
SCRIPT_DIR=$(dirname "$0")

exec "$SCRIPT_DIR/mkswu" --genkey "$@"

