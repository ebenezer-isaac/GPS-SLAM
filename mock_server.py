#!/usr/bin/env python3
"""
GPS-SLAM Mock Viewer Server

A GPU-free mock server that replicates the remote_viewer TCP protocol.
Generates synthetic rendered frames that respond to camera pose changes,
allowing full viewer development without a GPU.

Protocol: Compatible with remote_viewer.cpp, viewer_client.py, and web_viewer.py.

Usage:
    python3 mock_server.py                    # Default port 6688
    python3 mock_server.py --port 6688        # Custom port
    python3 mock_server.py --mode gradient     # Gradient scene (default)
    python3 mock_server.py --mode checkerboard # Checkerboard scene
    python3 mock_server.py --mode room         # Synthetic room scene
"""

import socket
import struct
import json
import numpy as np
import math
import time
import argparse
import signal
import sys
from typing import Tuple, Optional


class SyntheticScene:
    """Base class for synthetic scene renderers"""

    def render(self, pose: np.ndarray, width: int, height: int,
               fx: float, fy: float) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        """
        Render 4 images given a camera pose.

        Args:
            pose: 4x4 camera-to-world matrix
            width: image width
            height: image height
            fx: focal length x
            fy: focal length y

        Returns:
            (rendered_color, input_color, raycast_color, raycast_depth)
            Each is uint8 RGB array of shape (height, width, 3)
        """
        raise NotImplementedError


class GradientScene(SyntheticScene):
    """
    Renders a gradient skybox that shifts with camera orientation.
    Useful for verifying camera controls work correctly.
    """

    def render(self, pose, width, height, fx, fy):
        # Extract rotation and position from pose
        R = pose[:3, :3]
        t = pose[:3, 3]

        # Camera forward direction (Z axis of rotation)
        forward = R[:, 2]
        right = R[:, 0]
        up = R[:, 1]

        # Yaw and pitch from forward direction
        yaw = math.atan2(forward[0], forward[2])
        pitch = math.asin(np.clip(-forward[1], -1, 1))

        # Create pixel coordinates
        v, u = np.mgrid[0:height, 0:width].astype(np.float32)
        u_norm = (u - width / 2) / width   # [-0.5, 0.5]
        v_norm = (v - height / 2) / height  # [-0.5, 0.5]

        # Shift based on camera orientation
        u_shifted = u_norm + yaw / (2 * math.pi)
        v_shifted = v_norm + pitch / (2 * math.pi)

        # Create gradient colors that respond to camera pose
        r = ((np.sin(u_shifted * 4 * math.pi + t[0] * 2) + 1) * 0.5 * 200 + 55).astype(np.uint8)
        g = ((np.sin(v_shifted * 4 * math.pi + t[1] * 2) + 1) * 0.5 * 200 + 55).astype(np.uint8)
        b = ((np.sin((u_shifted + v_shifted) * 3 * math.pi + t[2] * 2) + 1) * 0.5 * 200 + 55).astype(np.uint8)

        rendered = np.stack([r, g, b], axis=-1)

        # Add crosshair in the center
        cx, cy = width // 2, height // 2
        rendered[cy-1:cy+2, max(0,cx-20):cx+20] = [255, 255, 255]
        rendered[max(0,cy-20):cy+20, cx-1:cx+2] = [255, 255, 255]

        # Add position text indicator as colored bar at top
        pos_color = np.array([
            int(abs(t[0] * 50) % 255),
            int(abs(t[1] * 50) % 255),
            int(abs(t[2] * 50) % 255)
        ], dtype=np.uint8)
        rendered[0:5, :] = pos_color

        # Input color: slightly different tint
        input_color = np.copy(rendered)
        input_color[:, :, 0] = np.clip(input_color[:, :, 0].astype(int) + 20, 0, 255).astype(np.uint8)

        # Raycast color: edge-highlighted version
        raycast_color = np.copy(rendered)
        raycast_color[::4, :] = np.clip(raycast_color[::4, :].astype(int) + 40, 0, 255).astype(np.uint8)
        raycast_color[:, ::4] = np.clip(raycast_color[:, ::4].astype(int) + 40, 0, 255).astype(np.uint8)

        # Raycast depth: distance-based coloring using jet colormap
        dist = np.sqrt(t[0]**2 + t[1]**2 + t[2]**2)
        depth_val = min(1.0, dist / 5.0)
        depth_img = self._jet_colormap(v_norm * 0.5 + 0.5 + depth_val * 0.1, width, height)

        return rendered, input_color, raycast_color, depth_img

    def _jet_colormap(self, values, width, height):
        """Simple jet colormap implementation"""
        values = np.clip(values, 0, 1)
        r = np.clip(1.5 - abs(4 * values - 3), 0, 1)
        g = np.clip(1.5 - abs(4 * values - 2), 0, 1)
        b = np.clip(1.5 - abs(4 * values - 1), 0, 1)
        img = np.stack([(r * 255).astype(np.uint8),
                        (g * 255).astype(np.uint8),
                        (b * 255).astype(np.uint8)], axis=-1)
        return img


class CheckerboardScene(SyntheticScene):
    """
    Renders a 3D checkerboard floor with perspective projection.
    Good for verifying perspective and movement.
    """

    def render(self, pose, width, height, fx, fy):
        R = pose[:3, :3]
        t = pose[:3, 3]

        # Generate ray directions for each pixel
        u = np.arange(width, dtype=np.float32)
        v = np.arange(height, dtype=np.float32)
        uu, vv = np.meshgrid(u, v)

        # Pixel to camera-space ray directions
        cx, cy = width / 2.0, height / 2.0
        dirs_cam = np.stack([
            (uu - cx) / fx,
            (vv - cy) / fy,
            np.ones_like(uu)
        ], axis=-1)  # (H, W, 3)

        # Transform to world space
        dirs_world = np.einsum('ij,...j->...i', R, dirs_cam)

        # Ray-plane intersection with y=0 plane (floor)
        # origin + t * direction, solve for y = -1 (floor at y=-1)
        floor_y = -1.0
        origin = t.copy()

        # t_hit = (floor_y - origin_y) / dir_y
        dir_y = dirs_world[:, :, 1]
        t_hit = np.where(abs(dir_y) > 1e-6, (floor_y - origin[1]) / dir_y, -1)

        # Compute intersection point
        hit_x = origin[0] + t_hit * dirs_world[:, :, 0]
        hit_z = origin[2] + t_hit * dirs_world[:, :, 2]

        # Checkerboard pattern
        checker = ((np.floor(hit_x) + np.floor(hit_z)).astype(int) % 2).astype(np.float32)

        # Mask: only show hits in front of camera and at reasonable distance
        mask = (t_hit > 0) & (t_hit < 50)

        # Color
        floor_r = np.where(mask, np.where(checker > 0.5, 200, 80), 30).astype(np.uint8)
        floor_g = np.where(mask, np.where(checker > 0.5, 200, 80), 30).astype(np.uint8)
        floor_b = np.where(mask, np.where(checker > 0.5, 220, 100), 50).astype(np.uint8)

        # Sky gradient for non-floor pixels
        sky_v = (vv / height * 255).astype(np.uint8)
        floor_r = np.where(mask, floor_r, 20)
        floor_g = np.where(mask, floor_g, np.clip(50 + sky_v // 3, 0, 255).astype(np.uint8))
        floor_b = np.where(mask, floor_b, np.clip(80 + sky_v // 2, 0, 255).astype(np.uint8))

        rendered = np.stack([floor_r, floor_g, floor_b], axis=-1)

        # Depth visualization (jet colormap)
        depth_norm = np.where(mask, np.clip(t_hit / 20.0, 0, 1), 1.0)
        depth_r = np.clip(1.5 - abs(4 * depth_norm - 3), 0, 1)
        depth_g = np.clip(1.5 - abs(4 * depth_norm - 2), 0, 1)
        depth_b = np.clip(1.5 - abs(4 * depth_norm - 1), 0, 1)
        depth_img = np.stack([(depth_r * 255).astype(np.uint8),
                              (depth_g * 255).astype(np.uint8),
                              (depth_b * 255).astype(np.uint8)], axis=-1)

        return rendered, rendered.copy(), rendered.copy(), depth_img


class RoomScene(SyntheticScene):
    """
    Renders a synthetic room with colored walls, floor, and ceiling.
    Mimics the Replica office0 scene structure.
    """

    def __init__(self):
        # Room bounds (similar to Replica office0)
        self.room_min = np.array([-3.0, -1.0, -3.0])
        self.room_max = np.array([3.0, 2.5, 3.0])

    def render(self, pose, width, height, fx, fy):
        R = pose[:3, :3]
        t = pose[:3, 3]

        u = np.arange(width, dtype=np.float32)
        v = np.arange(height, dtype=np.float32)
        uu, vv = np.meshgrid(u, v)

        cx, cy = width / 2.0, height / 2.0
        dirs_cam = np.stack([
            (uu - cx) / fx,
            (vv - cy) / fy,
            np.ones_like(uu)
        ], axis=-1)

        dirs_world = np.einsum('ij,...j->...i', R, dirs_cam)
        norms = np.linalg.norm(dirs_world, axis=-1, keepdims=True)
        dirs_world = dirs_world / (norms + 1e-8)

        # Ray-box intersection (AABB)
        origin = t.copy()
        img = np.full((height, width, 3), 30, dtype=np.uint8)
        depth_map = np.full((height, width), 100.0, dtype=np.float32)

        # Wall colors
        wall_colors = {
            'floor': np.array([150, 130, 100]),    # Brown floor
            'ceiling': np.array([240, 240, 240]),   # White ceiling
            'wall_x+': np.array([180, 100, 100]),   # Red wall
            'wall_x-': np.array([100, 180, 100]),   # Green wall
            'wall_z+': np.array([100, 100, 180]),   # Blue wall
            'wall_z-': np.array([180, 180, 100]),   # Yellow wall
        }

        # Check each face of the room box
        faces = [
            (1, self.room_min[1], 'floor', False),     # Floor (y = min)
            (1, self.room_max[1], 'ceiling', True),      # Ceiling (y = max)
            (0, self.room_min[0], 'wall_x-', False),   # Left wall
            (0, self.room_max[0], 'wall_x+', True),    # Right wall
            (2, self.room_min[2], 'wall_z-', False),   # Back wall
            (2, self.room_max[2], 'wall_z+', True),    # Front wall
        ]

        for axis, val, name, is_max in faces:
            d = dirs_world[:, :, axis]
            with np.errstate(divide='ignore', invalid='ignore'):
                t_hit = np.where(abs(d) > 1e-6, (val - origin[axis]) / d, -1)

            # Compute hit points
            hit = origin[np.newaxis, np.newaxis, :] + t_hit[:, :, np.newaxis] * dirs_world

            # Check bounds for the other two axes
            other_axes = [i for i in range(3) if i != axis]
            in_bounds = (t_hit > 0.01)
            for ax in other_axes:
                in_bounds &= (hit[:, :, ax] >= self.room_min[ax])
                in_bounds &= (hit[:, :, ax] <= self.room_max[ax])

            # Update pixels where this face is closer
            closer = in_bounds & (t_hit < depth_map)

            if np.any(closer):
                # Add checker/stripe pattern for visual interest
                ax1, ax2 = other_axes
                pattern_val = ((np.floor(hit[:, :, ax1] * 2) + np.floor(hit[:, :, ax2] * 2)).astype(int) % 2)
                brightness = np.where(pattern_val > 0, 1.0, 0.8)

                base_color = wall_colors[name]
                for c in range(3):
                    ch = (base_color[c] * brightness).astype(np.uint8)
                    img[:, :, c] = np.where(closer, ch, img[:, :, c])

                depth_map = np.where(closer, t_hit, depth_map)

        # Depth image as jet colormap
        depth_norm = np.clip(depth_map / 10.0, 0, 1)
        dr = np.clip(1.5 - abs(4 * depth_norm - 3), 0, 1)
        dg = np.clip(1.5 - abs(4 * depth_norm - 2), 0, 1)
        db = np.clip(1.5 - abs(4 * depth_norm - 1), 0, 1)
        depth_img = np.stack([(dr * 255).astype(np.uint8),
                              (dg * 255).astype(np.uint8),
                              (db * 255).astype(np.uint8)], axis=-1)

        # "Input" = rendered with slight color shift (simulating RGB input)
        input_color = np.clip(img.astype(int) + 10, 0, 255).astype(np.uint8)

        # "Raycast color" = same scene but with visible grid overlay
        raycast_color = img.copy()
        raycast_color[::20, :] = np.clip(raycast_color[::20, :].astype(int) + 50, 0, 255).astype(np.uint8)
        raycast_color[:, ::20] = np.clip(raycast_color[:, ::20].astype(int) + 50, 0, 255).astype(np.uint8)

        return img, input_color, raycast_color, depth_img


class MockViewerServer:
    """
    TCP server that mimics the remote_viewer binary protocol.
    Compatible with viewer_client.py and web_viewer.py.
    """

    def __init__(self, port: int = 6688, scene_mode: str = 'room'):
        self.port = port
        self.running = False

        # Select scene renderer
        scenes = {
            'gradient': GradientScene,
            'checkerboard': CheckerboardScene,
            'room': RoomScene,
        }
        if scene_mode not in scenes:
            print(f"Unknown scene mode '{scene_mode}', using 'room'")
            scene_mode = 'room'
        self.scene = scenes[scene_mode]()
        self.scene_mode = scene_mode

        print(f"Scene mode: {scene_mode}")

    def start(self):
        """Start the mock server"""
        self.running = True
        server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_socket.bind(('0.0.0.0', self.port))
        server_socket.listen(1)

        print(f"Mock GPS-SLAM server listening on port {self.port}")
        print(f"Connect with: python3 viewer_client.py --host localhost --port {self.port}")
        print(f"Or web:       python3 web_viewer.py --host localhost --port {self.port}")
        print()

        while self.running:
            try:
                print("Waiting for client connection...")
                server_socket.settimeout(1.0)
                try:
                    client_socket, addr = server_socket.accept()
                except socket.timeout:
                    continue

                print(f"Client connected from {addr}")
                self._handle_client(client_socket)
                print(f"Client {addr} disconnected")

            except KeyboardInterrupt:
                break
            except Exception as e:
                print(f"Error: {e}")

        server_socket.close()
        print("Server stopped")

    def _handle_client(self, client_socket: socket.socket):
        """Handle a single client connection"""
        frame_count = 0
        frame_times = []

        try:
            while self.running:
                start_time = time.time()

                # ---- RECEIVE: Camera Pose ----
                # Read 4-byte length prefix
                length_data = self._recv_exact(client_socket, 4)
                if not length_data:
                    break
                msg_length = struct.unpack('<I', length_data)[0]

                # Read JSON payload
                msg_data = self._recv_exact(client_socket, msg_length)
                if not msg_data:
                    break
                message = json.loads(msg_data.decode('utf-8'))

                # Parse camera parameters
                fov_x = message['fov_x']
                fov_y = message['fov_y']
                width = int(message['resolution_x'])
                height = int(message['resolution_y'])
                pose_flat = message['pose']

                # Reconstruct 4x4 pose matrix
                # Client sends column-major (Eigen convention), transpose to row-major
                pose = np.array(pose_flat, dtype=np.float32).reshape(4, 4).T

                # Apply the same Y/Z negation as remote_viewer.cpp
                pose[:, 1] *= -1  # Negate Y axis
                pose[:, 2] *= -1  # Negate Z axis

                # Compute intrinsics from FOV
                fx = width / (2.0 * math.tan(fov_x / 2.0))
                fy = height / (2.0 * math.tan(fov_y / 2.0))

                # ---- RENDER: Generate synthetic frames ----
                rendered, input_color, raycast_color, raycast_depth = \
                    self.scene.render(pose, width, height, fx, fy)

                # ---- SEND: Response (exact same protocol as remote_viewer.cpp) ----

                # Block 1-4: Four images
                for img in [rendered, input_color, raycast_color, raycast_depth]:
                    h, w = img.shape[:2]
                    client_socket.sendall(struct.pack('<I', w))
                    client_socket.sendall(struct.pack('<I', h))
                    client_socket.sendall(img.tobytes())

                # Block 5: Rotation matrix (9 floats, row-major)
                rotation = pose[:3, :3].astype(np.float32)
                client_socket.sendall(rotation.tobytes())

                # Block 6: Translation vector (3 floats)
                translation = pose[:3, 3].astype(np.float32)
                client_socket.sendall(translation.tobytes())

                # Block 7: Info string
                elapsed = time.time() - start_time
                fps_est = 1.0 / elapsed if elapsed > 0 else 0
                info = f"mock_server | frame {frame_count} | {fps_est:.1f} fps | {self.scene_mode}"
                info_bytes = info.encode('utf-8')
                client_socket.sendall(struct.pack('<I', len(info_bytes)))
                client_socket.sendall(info_bytes)

                # Block 8: MVP matrix (16 floats, row-major)
                mvp = pose.astype(np.float32)
                client_socket.sendall(mvp.tobytes())

                # Stats
                frame_count += 1
                frame_time = time.time() - start_time
                frame_times.append(frame_time)
                if len(frame_times) > 30:
                    frame_times.pop(0)
                avg_fps = 1.0 / (sum(frame_times) / len(frame_times)) if frame_times else 0

                if frame_count % 30 == 0:
                    pos = pose[:3, 3]
                    print(f"  Frame {frame_count} | {avg_fps:.1f} FPS | "
                          f"Pos: ({pos[0]:.2f}, {pos[1]:.2f}, {pos[2]:.2f}) | "
                          f"Resolution: {width}x{height}")

        except ConnectionError:
            pass
        except Exception as e:
            print(f"Client error: {e}")
        finally:
            client_socket.close()
            if frame_count > 0:
                avg = sum(frame_times) / len(frame_times) if frame_times else 0
                print(f"  Session: {frame_count} frames, avg {1.0/avg:.1f} FPS" if avg > 0 else "  Session ended")

    def _recv_exact(self, sock: socket.socket, size: int) -> Optional[bytes]:
        """Receive exactly 'size' bytes from socket"""
        data = b''
        while len(data) < size:
            try:
                chunk = sock.recv(size - len(data))
                if not chunk:
                    return None
                data += chunk
            except socket.timeout:
                continue
        return data


def main():
    parser = argparse.ArgumentParser(
        description="GPS-SLAM Mock Viewer Server (GPU-free)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Scene modes:
  gradient      - Colorful gradient that responds to camera orientation
  checkerboard  - 3D checkerboard floor with perspective projection
  room          - Synthetic room with colored walls (default, mimics Replica)

Examples:
  python3 mock_server.py                           # Start with default settings
  python3 mock_server.py --mode checkerboard       # Checkerboard scene
  python3 mock_server.py --port 7777               # Custom port
        """
    )
    parser.add_argument("--port", type=int, default=6688,
                        help="Server port (default: 6688)")
    parser.add_argument("--mode", type=str, default="room",
                        choices=["gradient", "checkerboard", "room"],
                        help="Scene rendering mode (default: room)")

    args = parser.parse_args()

    # Handle Ctrl+C gracefully
    server = MockViewerServer(port=args.port, scene_mode=args.mode)

    def signal_handler(sig, frame):
        print("\nShutting down...")
        server.running = False

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    print("=" * 50)
    print("  GPS-SLAM Mock Server")
    print(f"  Port: {args.port}")
    print(f"  Scene: {args.mode}")
    print("  No GPU required!")
    print("=" * 50)
    print()

    server.start()


if __name__ == "__main__":
    main()
