#!/bin/bash

# Configuration
# This script connects directly using local ssh/sshpass instead of Docker
# Uses a Jump Host (ProxyJump) to connect directly to the target GPU machine.

LOCAL_PORT="8081"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.connection_config"

# Defaults
DEFAULT_MACHINE=""
DEFAULT_USER=""
SSH_PASS=""

# Load defaults
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    DEFAULT_MACHINE="$MACHINE_NAME"
    DEFAULT_USER="$CS_USER"
    # SSH_PASS is loaded here if saved
fi

if [ "$#" -eq 2 ]; then
    MACHINE_NAME="$1"
    CS_USER="$2"
else
    # Interactive Mode
    echo "------------------------------------------------------------"
    read -p "Enter Machine Name [${DEFAULT_MACHINE}]: " INPUT_MACHINE
    MACHINE_NAME="${INPUT_MACHINE:-$DEFAULT_MACHINE}"
    
    read -p "Enter CS Username [${DEFAULT_USER}]: " INPUT_USER
    CS_USER="${INPUT_USER:-$DEFAULT_USER}"
    echo "------------------------------------------------------------"
    
    if [[ -z "$MACHINE_NAME" || -z "$CS_USER" ]]; then
        echo "Error: Machine name and username are required."
        exit 1
    fi
fi

# Password handling (if not using SSH keys)
if [ -z "$SSH_PASS" ]; then
    # Check if we have SSH keys set up
    KEY_FILE="$HOME/.ssh/id_ed25519"
    RSA_KEY="$HOME/.ssh/id_rsa"
    
    if [ ! -f "$KEY_FILE" ] && [ ! -f "$RSA_KEY" ]; then
        echo "No SSH keys or saved password found."
        echo -n "Enter UCL CS Password (to save for future): "
        read -s INPUT_PASS
        echo ""
        if [ -n "$INPUT_PASS" ]; then
             read -p "Save password to config? (Y/n) " SAVE_OPT
             if [[ "$SAVE_OPT" =~ ^[Yy]$ ]] || [[ -z "$SAVE_OPT" ]]; then
                 SSH_PASS="$INPUT_PASS"
             fi
        fi
    fi
fi

# Save config
echo "MACHINE_NAME=\"$MACHINE_NAME\"" > "$CONFIG_FILE"
echo "CS_USER=\"$CS_USER\"" >> "$CONFIG_FILE"
if [ -n "$SSH_PASS" ]; then
    echo "SSH_PASS=\"$SSH_PASS\"" >> "$CONFIG_FILE"
fi
chmod 600 "$CONFIG_FILE"

# AUTO-SETUP KEYS
if [ ! -f "$HOME/.ssh/id_ed25519" ] && [ ! -f "$HOME/.ssh/id_rsa" ]; then
    echo "(!) No SSH keys found."
    read -p "Do you want to run the one-time setup now? (Y/n) " SETUP_OPT
    if [[ "$SETUP_OPT" =~ ^[Yy]$ ]] || [[ -z "$SETUP_OPT" ]]; then
        bash "${SCRIPT_DIR}/setup_keys.sh"
    fi
fi

# Prepare SSH Command
JUMP_HOST="knuckles.cs.ucl.ac.uk"
TARGET_HOST="${MACHINE_NAME}.cs.ucl.ac.uk"

# Tunnel: Local 8081 -> Target 8443
TUNNEL_OPTS="-L ${LOCAL_PORT}:localhost:8443"
SSH_OPTS="-o StrictHostKeyChecking=no -t"

echo "============================================================"
echo "Connecting to ${TARGET_HOST}"
echo "Via Jump Host: ${JUMP_HOST}"
echo "Local Port: ${LOCAL_PORT} -> Remote Port: 443 (Guacamole)"
echo "------------------------------------------------------------"

# Check for sshpass
if command -v sshpass &> /dev/null; then
    if [ -n "$SSH_PASS" ]; then
        echo "Using saved password from config."
        export SSHPASS="$SSH_PASS"
        
        echo "Authentication: Auto (Hop 1) -> Manual (Hop 2)"
        sshpass -e ssh $SSH_OPTS -J "${CS_USER}@${JUMP_HOST}" $TUNNEL_OPTS "${CS_USER}@${TARGET_HOST}"
        exit
    fi
fi

# Manual Mode
echo "Enter your UCL CS password when prompted."
echo "------------------------------------------------------------"
echo "Keep this terminal open."
echo "Open your browser to: https://localhost:${LOCAL_PORT}/guacamole"
echo "============================================================"

ssh $SSH_OPTS -J "${CS_USER}@${JUMP_HOST}" $TUNNEL_OPTS "${CS_USER}@${TARGET_HOST}"
