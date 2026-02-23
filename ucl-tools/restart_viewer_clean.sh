#!/bin/bash
echo "=== Killing any existing remote_viewer ==="
killall -9 remote_viewer 2>/dev/null || true
sleep 2

# Verify dead
ps aux | grep remote_viewer | grep -v grep && echo "STILL RUNNING" || echo "Cleared"

# Check cached files
if [ ! -d /tmp/tsdf_engine_cache ]; then
    echo "Copying TSDF to /tmp..."
    cp -r output/release/replica/office0/tsdf_engine /tmp/tsdf_engine_cache
fi
if [ ! -f /tmp/gs_model_cache/model.pt ]; then
    mkdir -p /tmp/gs_model_cache
    cp -r output/release/replica/office0/gs_model/* /tmp/gs_model_cache/
fi
mkdir -p /tmp/gps_slam_viewer
ln -sf /tmp/gs_model_cache /tmp/gps_slam_viewer/gs_model
ln -sf /tmp/tsdf_engine_cache /tmp/gps_slam_viewer/tsdf_engine

echo ""
echo "=== Starting viewer ==="
nohup ./build/remote_viewer /tmp/viewer_fast.yaml > viewer_server.log 2>&1 &
echo "PID: $!"

echo "Waiting 20s for load..."
sleep 20
tail -3 viewer_server.log 2>/dev/null | tr '\r' '\n' | tail -3
ss -tlnp 2>/dev/null | grep 6688 && echo "READY!" || echo "Still loading..."
