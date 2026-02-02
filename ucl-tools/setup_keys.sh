#!/bin/bash

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.connection_config"

# Defaults
DEFAULT_MACHINE=""
DEFAULT_USER=""

# Load defaults
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    DEFAULT_MACHINE="$MACHINE_NAME"
    DEFAULT_USER="$CS_USER"
fi

echo "============================================================"
echo "  UCL SSH Key Setup (Zero-Touch Login)"
echo "============================================================"

# prompts
if [ -z "$DEFAULT_USER" ]; then
    read -p "Enter CS Username: " CS_USER
else
    read -p "Enter CS Username [${DEFAULT_USER}]: " INPUT_USER
    CS_USER="${INPUT_USER:-$DEFAULT_USER}"
fi

JUMP_HOST="knuckles.cs.ucl.ac.uk"

echo "------------------------------------------------------------"

# 1. Check/Generate Key
KEY_FILE="$HOME/.ssh/id_ed25519"
if [ ! -f "$KEY_FILE" ]; then
    echo "NO SSH Key found. Generating a new one..."
    ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -q
    echo "Key generated: $KEY_FILE"
else
    echo "Found existing key: $KEY_FILE"
fi

# 2. Copy Key to Server
echo "------------------------------------------------------------"
echo "Copying key to university server..."
echo "You will need to enter your password ONE LAST TIME."
echo "------------------------------------------------------------"

# Using ssh-copy-id
# We copy to the Jump Host (knuckles). Since home dirs are usually shared, 
# this often works for all CS machines.
ssh-copy-id -o StrictHostKeyChecking=no -i "${KEY_FILE}.pub" "${CS_USER}@${JUMP_HOST}"

if [ $? -eq 0 ]; then
    echo "------------------------------------------------------------"
    echo "SUCCESS: Key installed."
else
    echo "------------------------------------------------------------"
    echo "FAILED: Could not copy key. Please try running manually:"
    echo "ssh-copy-id ${CS_USER}@${JUMP_HOST}"
    exit 1
fi

# 3. Test Connection
echo "Testing connection (should be instant, no password)..."
ssh -o StrictHostKeyChecking=no -o BatchMode=yes "${CS_USER}@${JUMP_HOST}" "echo '  Authentication Verified! Server Time: \$(date)'"

if [ $? -eq 0 ]; then
    echo "============================================================"
    echo "SETUP COMPLETE!"
    echo "You can now run ./connect_local.sh without passwords."
    echo "============================================================"
else
    echo "WARNING: Key copy seemed to work, but automatic login failed."
fi
