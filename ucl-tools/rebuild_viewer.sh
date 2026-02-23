#!/bin/bash
# Pull latest code and rebuild remote_viewer on windcharger

echo "=== Pulling latest code ==="
git pull origin ucl-cs-dev 2>&1 || {
    echo "Pull failed, trying to reset and pull..."
    git stash 2>&1
    git pull origin ucl-cs-dev 2>&1
}

echo ""
echo "=== Building remote_viewer ==="
cd build
cmake .. 2>&1 | tail -5
make -j$(nproc) remote_viewer 2>&1 | tail -20
BUILD_STATUS=$?
cd ..

if [ $BUILD_STATUS -eq 0 ]; then
    echo ""
    echo "BUILD SUCCESS"
    ls -la build/remote_viewer
else
    echo ""
    echo "BUILD FAILED"
fi
