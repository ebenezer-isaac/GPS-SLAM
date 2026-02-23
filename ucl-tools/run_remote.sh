#!/bin/bash
# Remote Command Executor
# Writes commands to a local file, SCPs to windcharger, runs, returns output.
#
# Usage:
#   ./ucl-tools/run_remote.sh                   # Runs ucl-tools/remote_commands.sh
#   ./ucl-tools/run_remote.sh my_script.sh      # Runs a custom script
#
# Workflow:
#   1. Edit ucl-tools/remote_commands.sh with the commands you want to run
#   2. Run ./ucl-tools/run_remote.sh
#   3. Output is printed to terminal AND saved to ucl-tools/remote_output.txt

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.connection_config"

# Load config
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: No connection config found. Run connect_local.sh first."
    exit 1
fi

JUMP_HOST="knuckles.cs.ucl.ac.uk"
TARGET_HOST="${MACHINE_NAME}.cs.ucl.ac.uk"
REMOTE_PROJECT="/cs/student/project_msc/2025/seiot/eveerara/GPS-SLAM"

# Which script to run
LOCAL_SCRIPT="${1:-${SCRIPT_DIR}/remote_commands.sh}"
REMOTE_SCRIPT="${REMOTE_PROJECT}/ucl-tools/_remote_exec.sh"
OUTPUT_FILE="${SCRIPT_DIR}/remote_output.txt"

if [ ! -f "$LOCAL_SCRIPT" ]; then
    echo "Error: Script not found: $LOCAL_SCRIPT"
    echo "Create it with your commands, then run this again."
    exit 1
fi

echo "=== Remote Executor ==="
echo "Target: ${TARGET_HOST}"
echo "Script: ${LOCAL_SCRIPT}"
echo "========================"

# Build the wrapper that sets up the environment before running commands
WRAPPER="/tmp/remote_wrapper_$$.sh"
cat > "$WRAPPER" << 'ENVSETUP'
#!/bin/bash
set -e
cd /cs/student/project_msc/2025/seiot/eveerara/GPS-SLAM

# Setup CUDA and library paths
export PATH="/opt/cuda/cuda-12.4/bin:$PATH"
export LD_LIBRARY_PATH="./ThirdLibs/install/lib:./ThirdLibs/install/lib64:./ThirdLibs/libtorch/lib:/opt/cuda/cuda-12.4/lib64:$LD_LIBRARY_PATH"

echo "=== Environment ==="
echo "PWD: $(pwd)"
echo "CUDA: $(which nvcc 2>/dev/null || echo 'not found')"
echo "GPU: $(nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv,noheader 2>/dev/null || echo 'N/A')"
echo "==================="
echo ""

ENVSETUP

# Append the user's commands
cat "$LOCAL_SCRIPT" >> "$WRAPPER"

# SCP the wrapper to remote
SSH_OPTS="-o StrictHostKeyChecking=no -q"
if [ -n "$SSH_PASS" ] && command -v sshpass &> /dev/null; then
    export SSHPASS="$SSH_PASS"
    sshpass -e scp $SSH_OPTS -J "${CS_USER}@${JUMP_HOST}" "$WRAPPER" "${CS_USER}@${TARGET_HOST}:${REMOTE_SCRIPT}"
    sshpass -e ssh $SSH_OPTS -J "${CS_USER}@${JUMP_HOST}" "${CS_USER}@${TARGET_HOST}" "bash ${REMOTE_SCRIPT}" 2>&1 | tee "$OUTPUT_FILE"
else
    scp $SSH_OPTS -J "${CS_USER}@${JUMP_HOST}" "$WRAPPER" "${CS_USER}@${TARGET_HOST}:${REMOTE_SCRIPT}"
    ssh $SSH_OPTS -J "${CS_USER}@${JUMP_HOST}" "${CS_USER}@${TARGET_HOST}" "bash ${REMOTE_SCRIPT}" 2>&1 | tee "$OUTPUT_FILE"
fi

rm -f "$WRAPPER"
echo ""
echo "=== Output saved to: $OUTPUT_FILE ==="
