#!/bin/bash
# Script to run remote_viewer on UCL GPU machine
# Usage: bash run_remote_viewer.sh [start|stop|status|log]

PROJECT_DIR="/cs/student/project_msc/2025/seiot/eveerara/GPS-SLAM"
LOGFILE="$PROJECT_DIR/viewer_server.log"
PIDFILE="$PROJECT_DIR/viewer_server.pid"

# Setup environment
export PATH="/opt/cuda/cuda-12.4/bin:$PATH"
export LD_LIBRARY_PATH="$PROJECT_DIR/ThirdLibs/install/lib:$PROJECT_DIR/ThirdLibs/install/lib64:$PROJECT_DIR/ThirdLibs/libtorch/lib:/opt/cuda/cuda-12.4/lib64:$LD_LIBRARY_PATH"

cd "$PROJECT_DIR"

case "${1:-start}" in
    start)
        # Check for missing libs first
        echo "=== Checking shared libraries ==="
        MISSING=$(ldd build/remote_viewer 2>&1 | grep "not found")
        if [ -n "$MISSING" ]; then
            echo "WARNING: Missing libraries:"
            echo "$MISSING"
        else
            echo "All libraries OK"
        fi

        echo ""
        echo "=== Starting remote_viewer on port 6688 ==="
        echo "Config: configs/viewer/office0.yaml"
        echo "Model: output/mini/replica/office0/gs_model/model.pt"
        echo ""

        # Kill any existing viewer
        if [ -f "$PIDFILE" ]; then
            kill $(cat "$PIDFILE") 2>/dev/null
            rm -f "$PIDFILE"
        fi

        # Start viewer
        nohup ./build/remote_viewer configs/viewer/office0.yaml > "$LOGFILE" 2>&1 &
        echo $! > "$PIDFILE"
        echo "Viewer started with PID $(cat $PIDFILE)"
        sleep 3
        echo ""
        echo "=== Log output ==="
        cat "$LOGFILE"
        echo ""
        echo "=== GPU Memory ==="
        nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
        ;;
    stop)
        if [ -f "$PIDFILE" ]; then
            kill $(cat "$PIDFILE") 2>/dev/null
            rm -f "$PIDFILE"
            echo "Viewer stopped"
        else
            echo "No viewer running (no PID file)"
        fi
        ;;
    status)
        if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
            echo "Viewer running (PID $(cat $PIDFILE))"
        else
            echo "Viewer not running"
            rm -f "$PIDFILE" 2>/dev/null
        fi
        ;;
    log)
        cat "$LOGFILE" 2>/dev/null || echo "No log file"
        ;;
    *)
        echo "Usage: $0 [start|stop|status|log]"
        ;;
esac
