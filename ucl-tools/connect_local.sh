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

# Argument Parsing
# We support:
# 1. ./connect.sh                             (Uses defaults, interactive shell)
# 2. ./connect.sh <cmd>                       (Uses defaults, runs <cmd>)
# 3. ./connect.sh <machine> <user>            (No defaults, interactive shell)
# 4. ./connect.sh <machine> <user> <cmd>      (No defaults, runs <cmd>)

CMD_TO_RUN=""

if [ "$#" -ge 2 ] && [[ "$1" != -* ]] && [[ "$2" != -* ]]; then
    # Case 3 or 4: explicit machine/user provided
    MACHINE_NAME="$1"
    CS_USER="$2"
    shift 2
    CMD_TO_RUN="$*"
else
    # Case 1 or 2: rely on defaults
    MACHINE_NAME="$DEFAULT_MACHINE"
    CS_USER="$DEFAULT_USER"
    CMD_TO_RUN="$*"
    
    # Check if we are missing required info
    if [[ -z "$MACHINE_NAME" || -z "$CS_USER" ]]; then
        # Interactive Prompt Mode (Only if no command provided, OR we enforce prompts)
        echo "------------------------------------------------------------"
        read -p "Enter Machine Name [${DEFAULT_MACHINE}]: " INPUT_MACHINE
        MACHINE_NAME="${INPUT_MACHINE:-$DEFAULT_MACHINE}"
        
        read -p "Enter CS Username [${DEFAULT_USER}]: " INPUT_USER
        CS_USER="${INPUT_USER:-$DEFAULT_USER}"
        echo "------------------------------------------------------------"
    fi
fi

if [[ -z "$MACHINE_NAME" || -z "$CS_USER" ]]; then
    echo "Error: Machine name and username are required."
    exit 1
fi

# Password handling (if not using SSH keys)
if [ -z "$SSH_PASS" ]; then
    # Check if we have SSH keys set up
    KEY_FILE="$HOME/.ssh/id_ed25519"
    RSA_KEY="$HOME/.ssh/id_rsa"
    
    # Only prompt/setup if we are in interactive mode (no command) or if keys missing
    # To be safe: checks strict key existence.
    if [ ! -f "$KEY_FILE" ] && [ ! -f "$RSA_KEY" ]; then
        echo "No SSH keys or saved password found."
        
        # If we have a command to run, we can't reliably prompt without breaking output parsing.
        # But we'll try read -s (might fail in automation).
        
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
    # If automating, this prompt is skipped/blocks? 
    # For now, assume interactive if missing keys.
    if [ -z "$CMD_TO_RUN" ]; then
        read -p "Do you want to run the one-time setup now? (Y/n) " SETUP_OPT
        if [[ "$SETUP_OPT" =~ ^[Yy]$ ]] || [[ -z "$SETUP_OPT" ]]; then
            bash "${SCRIPT_DIR}/setup_keys.sh"
        fi
    fi
fi

# Prepare SSH Command
JUMP_HOST="knuckles.cs.ucl.ac.uk"
TARGET_HOST="${MACHINE_NAME}.cs.ucl.ac.uk"

# Tunnel: Local 8081 -> Target 8443
TUNNEL_OPTS="-L ${LOCAL_PORT}:localhost:8443"

# Persistence / Multiplexing
# Use a control socket to share connections. 
# This prevents "login spam" and makes subsequent commands instant.
SOCKET_DIR="$HOME/.ssh/sockets"
mkdir -p "$SOCKET_DIR"
CONTROL_SOCK="${SOCKET_DIR}/${CS_USER}@${JUMP_HOST}:22"
# Use a fixed socket name for easier cleanup
CONTROL_OPTS="-o ControlMaster=auto -o ControlPath=${CONTROL_SOCK} -o ControlPersist=600"

# Self-Healing: Check for stale socket
if [ -S "$CONTROL_SOCK" ]; then
    # Helper to check if socket is alive
    if ! ssh -O check -S "$CONTROL_SOCK" "ignored" 2>/dev/null; then
        echo "(!) Detected stale connection. Cleaning up..."
        rm -f "$CONTROL_SOCK"
    fi
fi

# Suppress "Address already in use" warnings with -q, but allow errors
SSH_OPTS="-q -o StrictHostKeyChecking=no -t ${CONTROL_OPTS}"

if [ -n "$CMD_TO_RUN" ]; then
    # Remote Execution Mode
    # We do NOT print banners to keep output clean for parsing
    REMOTE_CMD="$CMD_TO_RUN"
else
    # Interactive Mode
    echo "============================================================"
    echo "Connecting to ${TARGET_HOST}"
    echo "Via Jump Host: ${JUMP_HOST}"
    echo "Local Port: ${LOCAL_PORT} -> Remote Port: 443 (Guacamole)"
    echo "------------------------------------------------------------"
    REMOTE_CMD="clear; echo '---------------------------------------------------'; echo '  UCL GPU Workstation Tunnel Active'; echo '---------------------------------------------------'; echo 'Mounting Project Drive...'; echo 'if [ -f ~/.bashrc ]; then source ~/.bashrc; fi; alias my-project=\"cd /cs/student/project_msc/2025/seiot/eveerara/GPS-SLAM\"; cd /cs/student/project_msc/2025/seiot/eveerara/GPS-SLAM' > ~/.ucl_connect_rc; exec bash --rcfile ~/.ucl_connect_rc"
fi

# Execute
if command -v sshpass &> /dev/null; then
    if [ -n "$SSH_PASS" ]; then
        if [ -z "$CMD_TO_RUN" ]; then
            echo "Using saved password from config."
        fi
        export SSHPASS="$SSH_PASS"
        sshpass -e ssh $SSH_OPTS -J "${CS_USER}@${JUMP_HOST}" $TUNNEL_OPTS "${CS_USER}@${TARGET_HOST}" "$REMOTE_CMD"
        exit
    fi
fi

if [ -z "$CMD_TO_RUN" ]; then
    echo "Enter your UCL CS password when prompted."
    echo "------------------------------------------------------------"
    echo "Keep this terminal open."
    echo "Open your browser to: https://localhost:${LOCAL_PORT}/guacamole"
    echo "============================================================"
fi

ssh $SSH_OPTS -J "${CS_USER}@${JUMP_HOST}" $TUNNEL_OPTS "${CS_USER}@${TARGET_HOST}" "$REMOTE_CMD"

# If we ran a command (not interactive), pause so user can see output if window closes
if [ -n "$CMD_TO_RUN" ]; then
    echo ""
    echo "============================================================"
    echo "Command finished."
    # Only pause if connected to a terminal (interactive user)
    if [ -t 0 ]; then
        read -p "Press ENTER to close..."
    fi
fi
