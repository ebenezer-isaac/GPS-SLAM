# Check training progress on remote GPU
echo "=== Training Process ==="
ps aux | grep slam_trainer | grep -v grep || echo "No slam_trainer running"

echo ""
echo "=== GPU Status ==="
nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader

echo ""
echo "=== Last 30 Lines of Training Log ==="
tail -30 training_output.log 2>/dev/null || echo "No training log found"

echo ""
echo "=== Output Directory ==="
ls -la output/release/replica/office0/ 2>/dev/null || echo "No output yet"

echo ""
echo "=== Saved Files ==="
find output/release/replica/office0/ -type f 2>/dev/null | head -20 || echo "No files yet"
