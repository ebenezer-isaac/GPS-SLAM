# Session Recap: GPS-SLAM Viewer & Remote GPU Testing
**Date**: 23 February 2026
**Branch**: `ucl-cs-dev`
**Machine**: windcharger.cs.ucl.ac.uk (RTX 4090, 24GB VRAM, 60GB RAM)

---

## TL;DR

We connected to the UCL GPU machine (windcharger), ran the full GPS-SLAM training pipeline on the Replica office0 dataset (2000 frames), built a mock server for GPU-free development, and set up all the viewer infrastructure. The full trained model with **117,812 Gaussians** is ready on windcharger serving on port 6688.

---

## What We Built (New Files)

| File | Purpose |
|------|---------|
| `mock_server.py` | GPU-free Python server that replicates the remote_viewer TCP protocol. 3 synthetic scenes: room, gradient, checkerboard. Run on any machine without GPU. |
| `viewer_client.py` | Python/OpenCV interactive viewer. WASD + mouse controls. Connects to remote_viewer or mock_server over TCP. |
| `web_viewer.py` | Browser-based viewer. Wraps the TCP client in an HTTP server with a nice dark-themed UI. For demos. |
| `ucl-tools/run_remote.sh` | Remote command executor. Edit a script file, it SCPs it to windcharger, runs it via bash, returns output. Avoids all SSH encoding/quoting hell. |
| `ucl-tools/remote_commands.sh` | The editable commands file for `run_remote.sh`. Change this, run `./ucl-tools/run_remote.sh`, get output. |
| `ucl-tools/check_training.sh` | Checks training progress on remote: process status, GPU usage, log tail, output files. |
| `run_remote_viewer.sh` | Viewer server management: start/stop/status/log subcommands. |

---

## What Happened Step by Step

### 1. Connected to Windcharger
- Used the existing `connect-ucl-remote.sh` script (already configured for windcharger/eveerara)
- Confirmed RTX 4090 available, project at `/cs/student/project_msc/2025/seiot/eveerara/GPS-SLAM`
- Pre-built binaries exist (`build/slam_trainer`, `build/remote_viewer`)
- Replica office0 dataset fully downloaded at `data/replica/office0/`

### 2. Hit SSH Encoding Issues (Resolved)
**Problem**: The default shell on windcharger is **csh/tcsh**, not bash. This broke:
- Heredocs (`<<EOF`)
- Variable expansion (`$!`)
- Redirects (`2>/dev/null`)
- Quoting (double quotes parsed differently)

**Solution**: Created `ucl-tools/run_remote.sh` - writes commands to a local file, SCPs it to windcharger, runs it via `bash` explicitly. No more encoding issues. This was your suggestion and it works perfectly.

**How to use**:
```bash
# 1. Edit the commands file
vim ucl-tools/remote_commands.sh

# 2. Run it
./ucl-tools/run_remote.sh

# Or run a different script:
./ucl-tools/run_remote.sh ucl-tools/check_training.sh
```

### 3. Tested the Mini Model First
- The mini model was already trained (from a previous session): 6 frames, quarter resolution, 5168 Gaussians
- Started `remote_viewer` on windcharger with the mini model
- Set up SSH tunnel: `ssh -L 6688:localhost:6688 -J eveerara@knuckles.cs.ucl.ac.uk eveerara@windcharger.cs.ucl.ac.uk`
- Sent camera poses via Python test script through the tunnel

**Bug found**: Sent 320x240 resolution but model expected 1200x680 -> tensor size mismatch crash.
**Fix**: Resolution sent by client MUST exactly match the model's config resolution.

**Bug found**: Default camera pose (identity matrix) was at origin, outside the scene -> black frame.
**Fix**: Used actual training pose from `data/replica/office0/camera/pose000000.txt`.

Successfully captured 4 rendered frames through the tunnel (rendered color, input color, raycast color, raycast depth). Quality was low because the mini model only has 5168 Gaussians from 6 training frames.

### 4. Ran Full Replica Office0 Training
Started the full training on windcharger:
- **Config**: `configs/release/replica/office0.yaml`
- **Dataset**: 2000 frames, full resolution 1200x680
- **Settings**: 10000 max iterations, 20 local opt iters per frame, TSDF voxel_size=0.005

**Loading phase**: Took ~5 minutes to load all 2000 images into RAM (~46GB of the machine's 60GB). GPU was idle during this phase - all CPU work. I was worried about RAM, but the machine had 60GB total and it completed fine.

**Training phase**: SLAM loop processed all 2000 frames. The pipeline per frame: TSDF fusion (10.7ms) -> Gaussian init (18.9ms) -> local optimization (5.2ms).

**Results** (saved to `output/release/replica/office0/`):

| Output | Size | Description |
|--------|------|-------------|
| `gs_model/model.pt` | 27 MB | Gaussian model (117,812 splats) |
| `gs_model/point_cloud.ply` | 28 MB | Point cloud |
| `tsdf_mesh.ply` | **1.3 GB** | Full 3D reconstructed mesh |
| `tsdf_engine/` | 1.1 GB | TSDF volume (for viewer) |
| `val/render/` | 2000 images | Rendered frames from every pose |
| `val/gt/` | 2000 images | Ground truth images |
| `val/comp/` | 2000 images | Side-by-side comparisons |
| `val/pose/` | 2000 files | Estimated camera poses |
| `time_log.txt` | - | Performance: **25.25 FPS**, 3599 MB GPU |

**Key stats**: 117,812 Gaussians (23x more than mini), 25.25 FPS, 3599 MB GPU memory.

### 5. Started Viewer with Full Model
- Pulled latest code on windcharger (`git pull origin ucl-cs-dev`)
  - Had a merge conflict with `run_remote_viewer.sh` (we SCP'd it earlier, then committed it) -> resolved by removing the old file first
- Config `configs/viewer/office0.yaml` now points to `output/release/replica/office0`
- TSDF engine took ~2 minutes to load from NFS storage (1.1GB, slow university disk)
- Viewer is now running on windcharger, port 6688 listening

### 6. Fixed Viewer Resolution Bug
The web_viewer.py and viewer_client.py both defaulted to 640x480, but the model requires 1200x680. Updated:
- Camera defaults: width=1200, height=680
- FOV: fov_x=1.5708, fov_y=1.0297 (calculated from Replica intrinsics fx=fy=600)
- Added `--width` and `--height` CLI args to web_viewer.py

### 7. Built Mock Server
`mock_server.py` replicates the exact binary TCP protocol of `remote_viewer.cpp`:
- **Client -> Server**: 4-byte length prefix + JSON (fov_x, fov_y, resolution_x, resolution_y, pose[16 floats])
- **Server -> Client**: 4 images (each: uint32 w + uint32 h + w*h*3 RGB bytes) + rotation (9 floats) + translation (3 floats) + info string (uint32 len + string) + MVP matrix (16 floats)

Tested and verified: the protocol is fully compatible. `viewer_client.py` and `web_viewer.py` work against both the real server and the mock server with zero code changes.

Three scene modes:
- `room` (default): Colored walls, floor, ceiling with checker patterns. Mimics being inside a room.
- `checkerboard`: 3D floor with perspective, sky gradient. Good for verifying movement.
- `gradient`: Abstract gradient that shifts with camera rotation. Good for verifying controls.

### 8. Committed Everything
Commit `8d648f6` on `ucl-cs-dev`, pushed to `myfork`:
- All 7 new files listed above
- Updated `.gitignore` for `ucl-tools/remote_output.txt` and `ucl-tools/.connection_config`

---

## What's Working Right Now

### On Windcharger (UCL GPU)
- `remote_viewer` running with full model (PID 115683), port 6688 listening
- Full trained model: 117,812 Gaussians, 1.3GB mesh, 5.1GB eval images
- All output saved in `output/release/replica/office0/`

### On This Dev Container
- SSH tunnel can forward port 6688 from windcharger to localhost
- `web_viewer.py` connects to the viewer and serves a browser UI on port 8080
- `mock_server.py` works locally without GPU

---

## How to Demo (Class Tomorrow)

### Option A: Live from GPU (impressive but needs tunnel)
```bash
# Terminal 1: SSH tunnel
ssh -L 6688:localhost:6688 -J eveerara@knuckles.cs.ucl.ac.uk eveerara@windcharger.cs.ucl.ac.uk

# Terminal 2: Web viewer
python3 web_viewer.py --host localhost --port 6688 --web-port 8080

# Browser: http://localhost:8080
# Forward port 8080 in VS Code PORTS tab if using dev container
```

### Option B: Mock server (works anywhere, no GPU)
```bash
# Terminal 1: Mock server
python3 mock_server.py --mode room

# Terminal 2: Web viewer
python3 web_viewer.py --host localhost --port 6688 --web-port 8080

# Browser: http://localhost:8080
```

### Option C: Show saved images
The 2000 rendered images are saved on windcharger at:
- `output/release/replica/office0/val/render/` - what the model sees
- `output/release/replica/office0/val/comp/` - side-by-side with ground truth
- `output/release/replica/office0/val/gt/` - ground truth

SCP some back:
```bash
# From devcontainer:
scp -J eveerara@knuckles.cs.ucl.ac.uk eveerara@windcharger.cs.ucl.ac.uk:/cs/student/project_msc/2025/seiot/eveerara/GPS-SLAM/output/release/replica/office0/val/comp/frame000100_iter3980.color.jpg ./demo_frame.jpg
```

---

## Known Issues & Gotchas

1. **Resolution must match**: Client MUST send exactly 1200x680 (or whatever the model was trained at). Wrong resolution = instant crash (tensor size mismatch). The defaults are now correct.

2. **FOV must be correct**: Wrong FOV = wrong intrinsics = distorted rendering. Calculated from Replica intrinsics: `fov_x = 2 * atan(width / (2 * fx))` where fx=600.

3. **Camera pose at origin = black frame**: The Replica scene isn't at the origin. Use a known training pose or the viewer's built-in camera controls to navigate to the scene.

4. **Windcharger shell is csh**: Never try to run bash commands directly via SSH. Always use `ucl-tools/run_remote.sh` which forces bash.

5. **TSDF engine loading is slow**: The 1.1GB TSDF takes ~2 minutes to load on windcharger's NFS storage. Wait for "start viewer as server" in the log before connecting.

6. **Port forwarding in dev container**: The browser runs on Windows, web_viewer.py runs in the container. Must forward port 8080 in VS Code's PORTS tab.

7. **Single client**: The remote_viewer accepts only ONE client at a time. If the web_viewer crashes, restart it (and possibly the remote_viewer if it also crashed).

---

## Binary TCP Protocol (for reference)

This is the exact protocol that `remote_viewer.cpp`, `mock_server.py`, `viewer_client.py`, and `web_viewer.py` all share:

### Client -> Server
```
[4 bytes: uint32 message_length (little-endian)]
[message_length bytes: JSON UTF-8]
```
JSON fields: `fov_x`, `fov_y`, `resolution_x`, `resolution_y`, `pose` (16 floats, column-major 4x4 matrix)

### Server -> Client
```
Image 1 (rendered color):  [uint32 w][uint32 h][w*h*3 bytes RGB]
Image 2 (input color):     [uint32 w][uint32 h][w*h*3 bytes RGB]
Image 3 (raycast color):   [uint32 w][uint32 h][w*h*3 bytes RGB]
Image 4 (raycast depth):   [uint32 w][uint32 h][w*h*3 bytes RGB]
Rotation:                  [9 float32 = 36 bytes]
Translation:               [3 float32 = 12 bytes]
Info string:               [uint32 length][length bytes UTF-8]
MVP matrix:                [16 float32 = 64 bytes]
```

Server also negates Y and Z axes of the received pose and transposes column-major to row-major.

---

## Additional Issues We Hit & Solved

### 9. Resolution Mismatch Crash (Again)
The web_viewer.py and viewer_client.py both defaulted to 640x480, but the full model expects 1200x680. Sending wrong resolution crashes the remote_viewer instantly (tensor size mismatch). Fixed by updating Camera class defaults and adding `--width`/`--height` CLI args.

### 10. Duplicate Web Viewer Blocking
The remote_viewer only accepts ONE TCP client. If two web_viewer instances connect, the second one hangs forever. The first client holds the connection even if idle. Symptom: browser shows ERR_EMPTY_RESPONSE because the HTTP server thread is blocked waiting for a frame from the occupied remote_viewer. Solution: always kill old web_viewer processes before starting a new one.

### 11. Port Forwarding in Dev Container
The browser runs on Windows, the web_viewer runs in the Docker dev container. VS Code must forward port 8080 from the container to the host. Check the **PORTS** tab in VS Code's bottom panel. If it's not there, click "Add Port" and type 8080.

### 12. Slow TSDF Loading from NFS
The 1.1GB TSDF engine loads from NFS (university shared storage) and takes 5+ minutes. Solution: copy to local `/tmp` first:
```bash
cp -r output/release/replica/office0/tsdf_engine /tmp/tsdf_engine_cache
```
Then use a config that points to `/tmp`. This brings load time from 5+ minutes to ~10 seconds.

The `ucl-tools/remote_commands.sh` has a version that does this automatically.

---

## Session 2: Robustness Fixes (23 Feb, continued)

### 13. Remote Viewer Crash-on-Disconnect (ROOT CAUSE FIXED)

**Problem**: The C++ `remote_viewer.cpp` used a single `acceptor.accept(sock)` call followed by a while loop. When ANY client disconnected (even cleanly), boost::asio threw "End of file" or "Connection reset by peer", which was caught by the outer try-catch and **terminated the entire server process**. This meant:
- Every client disconnect killed the server
- Only one client could ever connect per server lifetime
- No way to reconnect without SSH-ing to windcharger and restarting manually

**Fix**: Wrapped the accept + serve logic in an **outer loop**:
```cpp
while (keep_running) {
    // Accept new client
    boost::asio::ip::tcp::socket sock(ios);
    acceptor.accept(sock);
    try {
        while (keep_running) {
            // Serve frames...
        }
    } catch (std::exception &e) {
        // Client disconnected - log it and loop back to accept
        std::cout << "Client disconnected: " << e.what() << std::endl;
    }
}
```
Also added `SO_REUSEADDR` so the port can be reused immediately after restart.

**Result**: Server now logs "Client disconnected" and goes back to "Waiting for client on port 6688..." instead of crashing. Tested and confirmed working.

### 14. Web Viewer Threading & Auto-Reconnect (ROOT CAUSE FIXED)

**Problem**: `web_viewer.py` used Python's `HTTPServer` which is **single-threaded**. When the browser requested `/frame`, the handler made a synchronous TCP call to the remote_viewer. If that call blocked (slow render, network delay), ALL other HTTP requests (including the initial page load) also blocked, causing the browser to show ERR_EMPTY_RESPONSE.

Additionally, if the TCP connection to remote_viewer dropped, web_viewer stayed disconnected forever with no recovery.

**Fixes applied**:
1. **ThreadedHTTPServer**: Replaced `HTTPServer` with `ThreadingMixIn + HTTPServer` so each browser request gets its own thread
2. **TCP lock**: Added `threading.Lock()` around `request_frame()` so only one thread sends/receives on the TCP socket at a time. Other threads get the cached last frame.
3. **Auto-reconnect**: When the TCP connection drops, a background thread automatically reconnects with exponential backoff (1s, 2s, 4s, max 10s)
4. **No exit on failure**: Web server starts even if initial connection fails, shows "Reconnecting..." in browser
5. **Browser-side**: JavaScript shows "Reconnecting..." status and slows polling to 1/sec when disconnected

### 15. Rebuilt and Deployed

- Pushed code to `myfork/ucl-cs-dev`
- Pulled on windcharger, rebuilt `remote_viewer` binary (`make -j remote_viewer`)
- Restarted viewer: new binary shows "Waiting for client on port 6688..." after client disconnects
- Web viewer confirmed serving frames (14KB JPEG per frame through tunnel)

---

## Current State (as of end of session 2)

### What's Running on Windcharger
- `remote_viewer` (PID 121253) serving on port 6688 (rebuilt with reconnect support)
- Using the full release model: 117,812 Gaussians
- TSDF engine loaded from `/tmp/tsdf_engine_cache` (fast local disk)
- GPU: ~1983 MiB / 24564 MiB used

### What's Running in the Dev Container
- SSH tunnel: `localhost:6688` -> `windcharger:6688`
- Web viewer: `localhost:3000` serving the browser UI
- Frame endpoint confirmed working: 14,667 bytes JPEG returned

### Browser Confirmed Working
- Port 3000 forwarded in VS Code PORTS tab
- `http://localhost:3000` loads the viewer in the browser
- WASD to navigate the 3D reconstructed office scene

---

## QUICK START: Copy-Paste to Get Viewer Running

### If remote_viewer is already running on windcharger (check first):
Paste this in the **devcontainer terminal** (VS Code):
```bash
# Step 1: SSH tunnel (runs in background, skip if already running)
ssh -f -N -L 6688:localhost:6688 -o StrictHostKeyChecking=no -J eveerara@knuckles.cs.ucl.ac.uk eveerara@windcharger.cs.ucl.ac.uk 2>/dev/null || echo "Tunnel already exists"

# Step 2: Kill old web viewer if any, start fresh
pkill -f web_viewer.py 2>/dev/null; sleep 1
nohup python3 web_viewer.py --host localhost --port 6688 --web-port 3000 > /tmp/web_viewer.log 2>&1 &
echo "Web viewer started. Forward port 3000 in VS Code PORTS tab, then open http://localhost:3000"
```

### If remote_viewer needs to be (re)started on windcharger:
Paste this in the **devcontainer terminal** (VS Code):
```bash
# Step 1: Restart remote_viewer on windcharger
./ucl-tools/run_remote.sh ucl-tools/restart_viewer_clean.sh

# Step 2: SSH tunnel (runs in background)
ssh -f -N -L 6688:localhost:6688 -o StrictHostKeyChecking=no -J eveerara@knuckles.cs.ucl.ac.uk eveerara@windcharger.cs.ucl.ac.uk 2>/dev/null || echo "Tunnel already exists"

# Step 3: Kill old web viewer if any, start fresh
pkill -f web_viewer.py 2>/dev/null; sleep 1
nohup python3 web_viewer.py --host localhost --port 6688 --web-port 3000 > /tmp/web_viewer.log 2>&1 &
echo "Web viewer started. Forward port 3000 in VS Code PORTS tab, then open http://localhost:3000"
```

### Then in VS Code:
1. Go to **PORTS** tab (bottom panel)
2. Click **Add Port** -> type **3000** -> Enter
3. Open **http://localhost:3000** in browser
4. Use **WASD** to move, **Arrow keys** to rotate, **Q/E** for up/down

### Mock server (no GPU, no tunnel, works anywhere):
```bash
python3 mock_server.py --mode room &
python3 web_viewer.py --host localhost --port 6688 --web-port 3000
# Open http://localhost:3000
```

---

## Next Steps

1. **SCP rendered outputs**: Copy the best evaluation images from windcharger to local for documentation/presentation

2. **Flutter viewer** (future): The architecture supports it. Flutter app would use `dart:io Socket` for raw TCP, send camera pose JSON, receive JPEG frames. Server-side rendering means Flutter just displays images - very doable.

3. **Live SLAM viewer** (future): Currently the viewer only works post-training (loads a saved model). Integrating it into the live SLAM loop (`slam_pipeline.cpp`) would allow watching reconstruction happen in real-time.

4. **Edge device integration**: When George/Akriti have the Jetson + camera pipeline ready, the same TCP protocol can stream live poses from the edge device to the GPU server.

5. **True multi-client support** (future): Currently the C++ server handles one client at a time (sequential). Multiple simultaneous viewers would need a thread-per-client or async architecture with shared GPU rendering.

---

## File Locations Quick Reference

```
VIEWERS:
  viewer_client.py          - Desktop viewer (OpenCV, WASD controls)
  web_viewer.py             - Browser viewer (HTTP on :3000)
  mock_server.py            - GPU-free mock server

REMOTE TOOLS:
  ucl-tools/run_remote.sh            - Run commands on windcharger
  ucl-tools/remote_commands.sh       - Commands to run (edit this)
  ucl-tools/check_training.sh        - Check training progress
  ucl-tools/restart_viewer_clean.sh  - Kill + restart remote_viewer
  ucl-tools/check_viewer.sh          - Check remote_viewer status/logs
  run_remote_viewer.sh               - Start/stop/status viewer

CONFIGS:
  configs/viewer/office0.yaml           - Viewer config (port 6688, release model)
  configs/release/replica/office0.yaml  - Full training (2000 frames)
  configs/mini/replica/office0.yaml     - Quick test (6 frames)

ON WINDCHARGER:
  output/release/replica/office0/
    gs_model/model.pt          - 27MB Gaussian model (117k splats)
    tsdf_mesh.ply              - 1.3GB reconstructed mesh
    tsdf_engine/               - 1.1GB TSDF volume
    val/render/                - 2000 rendered images
    val/gt/                    - 2000 ground truth images
    val/comp/                  - 2000 comparison images
    time_log.txt               - Performance stats
```
