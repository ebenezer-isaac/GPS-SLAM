#!/bin/bash

# Simple wrapper to launch the connection script from the root
# This is useful when running inside the Dev Container

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT_SCRIPT="${SCRIPT_DIR}/ucl-tools/connect_local.sh"

if [ -f "$CONNECT_SCRIPT" ]; then
    bash "$CONNECT_SCRIPT" "$@"
else
    echo "Error: Could not find connection script at $CONNECT_SCRIPT"
    exit 1
fi
