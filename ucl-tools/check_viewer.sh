#!/bin/bash
echo "=== remote_viewer process ==="
ps aux | grep remote_viewer | grep -v grep || echo "NOT RUNNING"

echo ""
echo "=== viewer_server.log ==="
tail -20 viewer_server.log 2>/dev/null | tr '\r' '\n' | tail -20

echo ""
echo "=== Port 6688 ==="
ss -tlnp 2>/dev/null | grep 6688 || echo "NOT LISTENING"
