#!/usr/bin/env python3
"""
GPS-SLAM Web Viewer

A web-based viewer that connects to the GPS-SLAM remote_viewer server
and streams rendered images to a browser interface.

Run this script and open http://localhost:8080 in your browser.
"""

import socket
import struct
import json
import numpy as np
import asyncio
import base64
from io import BytesIO
from http.server import HTTPServer, SimpleHTTPRequestHandler
import threading
import time
from dataclasses import dataclass, field
from typing import Optional
import sys

# Try to import PIL for image encoding
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    print("Warning: PIL not installed, using raw PNG encoding")

@dataclass  
class Camera:
    """Camera state for the viewer"""
    position: list = field(default_factory=lambda: [0.0, 0.0, 0.0])
    rotation: list = field(default_factory=lambda: [0.0, 0.0, 0.0])  # yaw, pitch, roll
    fov_x: float = 1.5708  # 2*atan(1200/(2*600)) for Replica office0
    fov_y: float = 1.0297  # 2*atan(680/(2*600)) for Replica office0
    width: int = 1200
    height: int = 680
    
    def get_pose_matrix(self) -> list:
        """Get 4x4 camera-to-world transformation matrix as flat list"""
        yaw, pitch, roll = self.rotation
        
        # Rotation matrices
        cy, sy = np.cos(yaw), np.sin(yaw)
        cp, sp = np.cos(pitch), np.sin(pitch)
        cr, sr = np.cos(roll), np.sin(roll)
        
        Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
        Rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
        Rz = np.array([[cr, -sr, 0], [sr, cr, 0], [0, 0, 1]])
        
        R = Ry @ Rx @ Rz
        
        pose = np.eye(4, dtype=np.float32)
        pose[:3, :3] = R
        pose[:3, 3] = self.position
        
        return pose.flatten().tolist()


class GPSSLAMClient:
    """Client for GPS-SLAM remote viewer server"""
    
    def __init__(self, host: str, port: int = 6688):
        self.host = host
        self.port = port
        self.socket: Optional[socket.socket] = None
        self.camera = Camera()
        self.connected = False
        self.last_frame: Optional[bytes] = None
        self.last_frame_time = 0
        self.fps = 0.0
        self.lock = threading.Lock()
        
    def connect(self) -> bool:
        """Connect to the remote viewer server"""
        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(5)
            self.socket.connect((self.host, self.port))
            self.connected = True
            print(f"Connected to {self.host}:{self.port}")
            return True
        except Exception as e:
            print(f"Failed to connect: {e}")
            self.connected = False
            return False
    
    def disconnect(self):
        """Disconnect from server"""
        if self.socket:
            self.socket.close()
            self.socket = None
        self.connected = False
    
    def _recv_exact(self, size: int) -> bytes:
        """Receive exactly 'size' bytes from socket"""
        data = b''
        while len(data) < size:
            chunk = self.socket.recv(size - len(data))
            if not chunk:
                raise ConnectionError("Connection closed")
            data += chunk
        return data
    
    def request_frame(self) -> Optional[bytes]:
        """Send camera pose and receive rendered frame as JPEG bytes"""
        if not self.connected:
            return None
            
        try:
            # Send camera pose as JSON
            message = {
                "fov_x": self.camera.fov_x,
                "fov_y": self.camera.fov_y,
                "resolution_x": float(self.camera.width),
                "resolution_y": float(self.camera.height),
                "pose": self.camera.get_pose_matrix()
            }
            
            msg_bytes = json.dumps(message).encode('utf-8')
            length = struct.pack('<I', len(msg_bytes))
            self.socket.sendall(length + msg_bytes)
            
            # Receive rendered image
            width_data = self._recv_exact(4)
            height_data = self._recv_exact(4)
            width = struct.unpack('<I', width_data)[0]
            height = struct.unpack('<I', height_data)[0]
            
            img_size = width * height * 3
            img_data = self._recv_exact(img_size)
            
            # Skip additional server data (3 more images + tensors + string)
            for _ in range(3):
                w = struct.unpack('<I', self._recv_exact(4))[0]
                h = struct.unpack('<I', self._recv_exact(4))[0]
                self._recv_exact(w * h * 3)
            
            self._recv_exact(9 * 4)  # rotation
            self._recv_exact(3 * 4)  # translation
            info_len = struct.unpack('<I', self._recv_exact(4))[0]
            self._recv_exact(info_len)  # info string
            self._recv_exact(16 * 4)  # MVP matrix
            
            # Convert to JPEG
            img_array = np.frombuffer(img_data, dtype=np.uint8).reshape(height, width, 3)
            
            if HAS_PIL:
                img = Image.fromarray(img_array, 'RGB')
                buffer = BytesIO()
                img.save(buffer, format='JPEG', quality=85)
                jpeg_bytes = buffer.getvalue()
            else:
                # Fallback: return raw RGB (less efficient)
                jpeg_bytes = img_data
            
            # Update stats
            now = time.time()
            if self.last_frame_time > 0:
                self.fps = 1.0 / (now - self.last_frame_time)
            self.last_frame_time = now
            
            with self.lock:
                self.last_frame = jpeg_bytes
            
            return jpeg_bytes
            
        except Exception as e:
            print(f"Error requesting frame: {e}")
            self.connected = False
            return None
    
    def update_camera(self, action: str, value: float = 1.0):
        """Update camera based on action"""
        speed = 0.05 * value
        rot_speed = 0.03 * value
        
        yaw = self.camera.rotation[0]
        
        if action == 'forward':
            self.camera.position[0] += np.sin(yaw) * speed
            self.camera.position[2] += np.cos(yaw) * speed
        elif action == 'backward':
            self.camera.position[0] -= np.sin(yaw) * speed
            self.camera.position[2] -= np.cos(yaw) * speed
        elif action == 'left':
            self.camera.position[0] -= np.cos(yaw) * speed
            self.camera.position[2] += np.sin(yaw) * speed
        elif action == 'right':
            self.camera.position[0] += np.cos(yaw) * speed
            self.camera.position[2] -= np.sin(yaw) * speed
        elif action == 'up':
            self.camera.position[1] += speed
        elif action == 'down':
            self.camera.position[1] -= speed
        elif action == 'rotate_left':
            self.camera.rotation[0] -= rot_speed
        elif action == 'rotate_right':
            self.camera.rotation[0] += rot_speed
        elif action == 'rotate_up':
            self.camera.rotation[1] = max(-1.5, self.camera.rotation[1] - rot_speed)
        elif action == 'rotate_down':
            self.camera.rotation[1] = min(1.5, self.camera.rotation[1] + rot_speed)
        elif action == 'reset':
            self.camera.position = [0.0, 0.0, 0.0]
            self.camera.rotation = [0.0, 0.0, 0.0]


# Global client instance
client: Optional[GPSSLAMClient] = None

# HTML page with viewer interface
HTML_PAGE = '''<!DOCTYPE html>
<html>
<head>
    <title>GPS-SLAM Viewer</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #1a1a2e;
            color: #eee;
            height: 100vh;
            display: flex;
            flex-direction: column;
        }
        .header {
            background: #16213e;
            padding: 15px 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .header h1 {
            font-size: 1.5rem;
            color: #4cc9f0;
        }
        .status {
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9rem;
        }
        .status.connected { background: #2d6a4f; }
        .status.disconnected { background: #9d0208; }
        .main {
            flex: 1;
            display: flex;
            padding: 20px;
            gap: 20px;
        }
        .viewer-container {
            flex: 1;
            background: #0f0f23;
            border-radius: 10px;
            overflow: hidden;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        #viewer {
            max-width: 100%;
            max-height: 100%;
        }
        .controls {
            width: 280px;
            background: #16213e;
            border-radius: 10px;
            padding: 20px;
        }
        .controls h3 {
            color: #4cc9f0;
            margin-bottom: 15px;
            font-size: 1.1rem;
        }
        .info-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
            margin-bottom: 20px;
        }
        .info-item {
            background: #0f0f23;
            padding: 10px;
            border-radius: 5px;
            text-align: center;
        }
        .info-item label {
            font-size: 0.75rem;
            color: #888;
            display: block;
        }
        .info-item span {
            font-size: 1.1rem;
            color: #4cc9f0;
        }
        .keys-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 5px;
            margin-bottom: 20px;
        }
        .key {
            background: #0f0f23;
            border: 1px solid #333;
            border-radius: 5px;
            padding: 12px;
            text-align: center;
            cursor: pointer;
            transition: all 0.2s;
            font-size: 0.9rem;
        }
        .key:hover { background: #1a1a3e; border-color: #4cc9f0; }
        .key:active, .key.active { background: #4cc9f0; color: #000; }
        .key.empty { visibility: hidden; }
        .help {
            font-size: 0.8rem;
            color: #666;
            line-height: 1.6;
        }
        .help kbd {
            background: #0f0f23;
            padding: 2px 6px;
            border-radius: 3px;
            border: 1px solid #333;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🌌 GPS-SLAM Viewer</h1>
        <div id="status" class="status disconnected">Connecting...</div>
    </div>
    <div class="main">
        <div class="viewer-container">
            <img id="viewer" alt="Waiting for frames...">
        </div>
        <div class="controls">
            <h3>📊 Stats</h3>
            <div class="info-grid">
                <div class="info-item">
                    <label>FPS</label>
                    <span id="fps">0</span>
                </div>
                <div class="info-item">
                    <label>Latency</label>
                    <span id="latency">0ms</span>
                </div>
            </div>
            
            <h3>🎮 Movement</h3>
            <div class="keys-grid">
                <div class="key empty"></div>
                <div class="key" data-action="forward">W<br>↑</div>
                <div class="key empty"></div>
                <div class="key" data-action="left">A<br>←</div>
                <div class="key" data-action="backward">S<br>↓</div>
                <div class="key" data-action="right">D<br>→</div>
            </div>
            
            <h3>🔄 Rotation</h3>
            <div class="keys-grid">
                <div class="key empty"></div>
                <div class="key" data-action="rotate_up">↑</div>
                <div class="key empty"></div>
                <div class="key" data-action="rotate_left">←</div>
                <div class="key" data-action="rotate_down">↓</div>
                <div class="key" data-action="rotate_right">→</div>
            </div>
            
            <div class="keys-grid" style="grid-template-columns: 1fr 1fr;">
                <div class="key" data-action="up">Q Up</div>
                <div class="key" data-action="down">E Down</div>
            </div>
            
            <div class="key" data-action="reset" style="width: 100%; margin-top: 10px;">R - Reset Camera</div>
            
            <h3 style="margin-top: 20px;">⌨️ Keyboard</h3>
            <div class="help">
                <kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> - Move<br>
                <kbd>Q</kbd><kbd>E</kbd> - Up/Down<br>
                <kbd>↑</kbd><kbd>↓</kbd><kbd>←</kbd><kbd>→</kbd> - Rotate<br>
                <kbd>R</kbd> - Reset camera
            </div>
        </div>
    </div>

    <script>
        const viewer = document.getElementById('viewer');
        const statusEl = document.getElementById('status');
        const fpsEl = document.getElementById('fps');
        const latencyEl = document.getElementById('latency');
        
        let lastFrameTime = Date.now();
        let activeKeys = new Set();
        
        // Fetch frames continuously
        async function fetchFrame() {
            const start = Date.now();
            try {
                const response = await fetch('/frame?' + Date.now());
                if (response.ok) {
                    const blob = await response.blob();
                    viewer.src = URL.createObjectURL(blob);
                    
                    const now = Date.now();
                    const latency = now - start;
                    const fps = 1000 / (now - lastFrameTime);
                    lastFrameTime = now;
                    
                    fpsEl.textContent = fps.toFixed(1);
                    latencyEl.textContent = latency + 'ms';
                    
                    statusEl.textContent = 'Connected';
                    statusEl.className = 'status connected';
                }
            } catch (e) {
                statusEl.textContent = 'Disconnected';
                statusEl.className = 'status disconnected';
            }
            
            requestAnimationFrame(fetchFrame);
        }
        
        // Send control commands
        async function sendControl(action) {
            try {
                await fetch('/control?action=' + action);
            } catch (e) {}
        }
        
        // Button controls
        document.querySelectorAll('.key[data-action]').forEach(btn => {
            btn.addEventListener('mousedown', () => {
                sendControl(btn.dataset.action);
                btn.classList.add('active');
            });
            btn.addEventListener('mouseup', () => btn.classList.remove('active'));
            btn.addEventListener('mouseleave', () => btn.classList.remove('active'));
        });
        
        // Keyboard controls
        const keyMap = {
            'KeyW': 'forward', 'ArrowUp': 'rotate_up',
            'KeyS': 'backward', 'ArrowDown': 'rotate_down',
            'KeyA': 'left', 'ArrowLeft': 'rotate_left',
            'KeyD': 'right', 'ArrowRight': 'rotate_right',
            'KeyQ': 'up', 'KeyE': 'down',
            'KeyR': 'reset'
        };
        
        document.addEventListener('keydown', (e) => {
            const action = keyMap[e.code];
            if (action && !activeKeys.has(e.code)) {
                activeKeys.add(e.code);
                sendControl(action);
            }
        });
        
        document.addEventListener('keyup', (e) => {
            activeKeys.delete(e.code);
        });
        
        // Continuous key repeat
        setInterval(() => {
            activeKeys.forEach(code => {
                const action = keyMap[code];
                if (action && action !== 'reset') {
                    sendControl(action);
                }
            });
        }, 50);
        
        // Start fetching
        fetchFrame();
    </script>
</body>
</html>
'''


class ViewerHandler(SimpleHTTPRequestHandler):
    """HTTP request handler for the web viewer"""
    
    def log_message(self, format, *args):
        pass  # Suppress logs
    
    def do_GET(self):
        global client
        
        if self.path == '/' or self.path == '/index.html':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(HTML_PAGE.encode())
            
        elif self.path.startswith('/frame'):
            if client and client.connected:
                frame = client.request_frame()
                if frame:
                    self.send_response(200)
                    self.send_header('Content-Type', 'image/jpeg')
                    self.send_header('Cache-Control', 'no-cache')
                    self.end_headers()
                    self.wfile.write(frame)
                    return
            
            self.send_response(503)
            self.end_headers()
            
        elif self.path.startswith('/control'):
            if client:
                action = self.path.split('action=')[-1].split('&')[0]
                client.update_camera(action)
            self.send_response(200)
            self.end_headers()
            
        else:
            self.send_response(404)
            self.end_headers()


def main():
    global client
    
    import argparse
    parser = argparse.ArgumentParser(description="GPS-SLAM Web Viewer")
    parser.add_argument("--host", type=str, default="localhost",
                        help="GPS-SLAM server hostname")
    parser.add_argument("--port", type=int, default=6688,
                        help="GPS-SLAM server port")
    parser.add_argument("--web-port", type=int, default=8080,
                        help="Web server port")
    parser.add_argument("--width", type=int, default=1200,
                        help="Render width (must match model config, default: 1200)")
    parser.add_argument("--height", type=int, default=680,
                        help="Render height (must match model config, default: 680)")
    args = parser.parse_args()

    print(f"Connecting to GPS-SLAM server at {args.host}:{args.port}...")
    client = GPSSLAMClient(args.host, args.port)
    client.camera.width = args.width
    client.camera.height = args.height
    # Calculate FOV from Replica office0 intrinsics (fx=600, fy=600)
    import math
    client.camera.fov_x = 2 * math.atan(args.width / (2 * 600))
    client.camera.fov_y = 2 * math.atan(args.height / (2 * 600))
    
    if not client.connect():
        print("Failed to connect to GPS-SLAM server")
        print("Make sure the remote_viewer is running and port forwarding is set up")
        sys.exit(1)
    
    print(f"\n{'='*50}")
    print(f"  GPS-SLAM Web Viewer")
    print(f"  Open http://localhost:{args.web_port} in your browser")
    print(f"{'='*50}\n")
    
    server = HTTPServer(('0.0.0.0', args.web_port), ViewerHandler)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        client.disconnect()


if __name__ == "__main__":
    main()
