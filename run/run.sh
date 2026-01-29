#!/usr/bin/env bash
set -euo pipefail

# Optional overrides allow quick experiments without editing this script.
# Examples:
#   RUN_TRAIN_ARGS="--dry-run" bash run/run.sh
#   RUN_CONFIG_DIR=configs/mini RUN_OUTPUT_BASE=output/mini bash run/run.sh

CONFIG_DIR=${RUN_CONFIG_DIR:-configs/release}
OUTPUT_BASE=${RUN_OUTPUT_BASE:-output/release}
REPLICA_RESULTS_ROOT=${RUN_REPLICA_RESULTS_ROOT:-${OUTPUT_BASE}/replica}
GPS_RESULTS_ROOT=${RUN_GPS_RESULTS_ROOT:-${OUTPUT_BASE}/gps_slam}

python3 run/train.py --config-dir "${CONFIG_DIR}" ${RUN_TRAIN_ARGS:-}
python3 run/eval.py --base-path "${OUTPUT_BASE}" ${RUN_EVAL_ARGS:-}
python3 run/read_results.py --root_dir "${REPLICA_RESULTS_ROOT}" ${RUN_REPLICA_RESULTS_ARGS:-}
python3 run/read_results.py --root_dir "${GPS_RESULTS_ROOT}" ${RUN_GPS_RESULTS_ARGS:-}
