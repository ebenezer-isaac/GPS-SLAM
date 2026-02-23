#!/usr/bin/env python3
"""
GPS-SLAM Real-time Viewer Client

A Python client that connects to the GPS-SLAM remote_viewer server
and allows interactive camera navigation.

Controls:
  W/S - Move forward/backward
  A/D - Strafe left/right
  Q/E - Move up/down
  Arrow keys - Rotate camera
  Mouse drag - Look around
  +/- - Adjust move speed
  ESC - Quit
"""

import socket
import struct
import json
import numpy as np
import cv2
import threading
import time
from dataclasses import dataclass
from typing import Optional

@dataclass
class Camera:
    """Camera state for the viewer"""
    position: np.ndarray  # x, y, z
    rotation: np.ndarray  # yaw, pitch, roll (in radians)
    fov_x: float = 1.5708  # 2*atan(1200/(2*600)) for Replica office0
    fov_y: float = 1.0297  # 2*atan(680/(2*600)) for Replica office0
    width: int = 1200
    height: int = 680
    
    def get_pose_matrix(self) -> np.ndarray:
        """Get 4x4 camera-to-world transformation matrix"""
        yaw, pitch, roll = self.rotation
        
        # Rotation matrices
        Ry = np.array([
            [np.cos(yaw), 0, np.sin(yaw)],
            [0, 1, 0],
            [-np.sin(yaw), 0, np.cos(yaw)]
        ])
        Rx = np.array([
            [1, 0, 0],
            [0, np.cos(pitch), -np.sin(pitch)],
            [0, np.sin(pitch), np.cos(pitch)]
        ])
        Rz = np.array([
            [np.cos(roll), -np.sin(roll), 0],
            [np.sin(roll), np.cos(roll), 0],
            [0, 0, 1]
        ])
        
        R = Ry @ Rx @ Rz
        
        # Build 4x4 matrix
        pose = np.eye(4, dtype=np.float32)
        pose[:3, :3] = R
        pose[:3, 3] = self.position
        
        return pose
    
    def get_forward(self) -> np.ndarray:
        """Get forward direction vector"""
        yaw, pitch, _ = self.rotation
        return np.array([
            np.sin(yaw) * np.cos(pitch),
            -np.sin(pitch),
            np.cos(yaw) * np.cos(pitch)
        ])
    
    def get_right(self) -> np.ndarray:
        """Get right direction vector"""
        yaw = self.rotation[0]
        return np.array([np.cos(yaw), 0, -np.sin(yaw)])
    
    def get_up(self) -> np.ndarray:
        """Get up direction vector"""
        return np.array([0, 1, 0])


class GPSSLAMViewerClient:
    """Client for GPS-SLAM remote viewer"""
    
    def __init__(self, host: str, port: int = 6688):
        self.host = host
        self.port = port
        self.socket: Optional[socket.socket] = None
        self.camera = Camera(
            position=np.array([0.0, 0.0, 0.0], dtype=np.float32),
            rotation=np.array([0.0, 0.0, 0.0], dtype=np.float32)
        )
        self.move_speed = 0.05
        self.rotate_speed = 0.02
        self.running = False
        self.last_frame: Optional[np.ndarray] = None
        self.fps = 0.0
        
        # Mouse state
        self.mouse_down = False
        self.last_mouse_x = 0
        self.last_mouse_y = 0
        
    def connect(self) -> bool:
        """Connect to the remote viewer server"""
        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.connect((self.host, self.port))
            print(f"Connected to {self.host}:{self.port}")
            return True
        except Exception as e:
            print(f"Failed to connect: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from server"""
        if self.socket:
            self.socket.close()
            self.socket = None
    
    def send_camera_pose(self):
        """Send current camera pose to server"""
        # Build message as JSON
        pose_matrix = self.camera.get_pose_matrix()
        
        message = {
            "fov_x": float(self.camera.fov_x),
            "fov_y": float(self.camera.fov_y),
            "resolution_x": float(self.camera.width),
            "resolution_y": float(self.camera.height),
            "pose": pose_matrix.flatten().tolist()  # Column-major for Eigen
        }
        
        msg_bytes = json.dumps(message).encode('utf-8')
        
        # Send length prefix (4 bytes) + message
        length = struct.pack('<I', len(msg_bytes))
        self.socket.sendall(length + msg_bytes)
    
    def receive_image(self) -> Optional[np.ndarray]:
        """Receive rendered image from server"""
        try:
            # Read width and height
            width_data = self._recv_exact(4)
            height_data = self._recv_exact(4)
            
            width = struct.unpack('<I', width_data)[0]
            height = struct.unpack('<I', height_data)[0]
            
            # Read RGB data
            img_size = width * height * 3
            img_data = self._recv_exact(img_size)
            
            # Convert to numpy array (RGB format from server)
            img = np.frombuffer(img_data, dtype=np.uint8).reshape(height, width, 3)
            
            # Convert RGB to BGR for OpenCV
            img = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
            
            return img
        except Exception as e:
            print(f"Error receiving image: {e}")
            return None
    
    def receive_additional_data(self):
        """Receive additional images and data sent by server"""
        try:
            # Server sends: rendered_color, input_color, raycast_color, raycast_depth
            # Plus: rotation tensor, translation tensor, info string, mvp tensor
            
            # Skip additional images (3 more)
            for _ in range(3):
                width_data = self._recv_exact(4)
                height_data = self._recv_exact(4)
                width = struct.unpack('<I', width_data)[0]
                height = struct.unpack('<I', height_data)[0]
                self._recv_exact(width * height * 3)
            
            # Skip rotation (9 floats)
            self._recv_exact(9 * 4)
            
            # Skip translation (3 floats)  
            self._recv_exact(3 * 4)
            
            # Read info string
            info_len_data = self._recv_exact(4)
            info_len = struct.unpack('<I', info_len_data)[0]
            self._recv_exact(info_len)
            
            # Skip MVP matrix (16 floats)
            self._recv_exact(16 * 4)
            
        except Exception as e:
            print(f"Error receiving additional data: {e}")
    
    def _recv_exact(self, size: int) -> bytes:
        """Receive exactly 'size' bytes from socket"""
        data = b''
        while len(data) < size:
            chunk = self.socket.recv(size - len(data))
            if not chunk:
                raise ConnectionError("Connection closed")
            data += chunk
        return data
    
    def handle_input(self, key: int):
        """Handle keyboard input"""
        # Movement
        if key == ord('w'):
            self.camera.position += self.camera.get_forward() * self.move_speed
        elif key == ord('s'):
            self.camera.position -= self.camera.get_forward() * self.move_speed
        elif key == ord('a'):
            self.camera.position -= self.camera.get_right() * self.move_speed
        elif key == ord('d'):
            self.camera.position += self.camera.get_right() * self.move_speed
        elif key == ord('q'):
            self.camera.position += self.camera.get_up() * self.move_speed
        elif key == ord('e'):
            self.camera.position -= self.camera.get_up() * self.move_speed
        
        # Rotation with arrow keys
        elif key == 81:  # Left arrow
            self.camera.rotation[0] -= self.rotate_speed
        elif key == 83:  # Right arrow
            self.camera.rotation[0] += self.rotate_speed
        elif key == 82:  # Up arrow
            self.camera.rotation[1] -= self.rotate_speed
        elif key == 84:  # Down arrow
            self.camera.rotation[1] += self.rotate_speed
        
        # Speed adjustment
        elif key == ord('+') or key == ord('='):
            self.move_speed *= 1.2
            print(f"Move speed: {self.move_speed:.3f}")
        elif key == ord('-'):
            self.move_speed /= 1.2
            print(f"Move speed: {self.move_speed:.3f}")
        
        # Reset
        elif key == ord('r'):
            self.camera.position = np.array([0.0, 0.0, 0.0], dtype=np.float32)
            self.camera.rotation = np.array([0.0, 0.0, 0.0], dtype=np.float32)
            print("Camera reset")
    
    def mouse_callback(self, event, x, y, flags, param):
        """Handle mouse events for camera rotation"""
        if event == cv2.EVENT_LBUTTONDOWN:
            self.mouse_down = True
            self.last_mouse_x = x
            self.last_mouse_y = y
        elif event == cv2.EVENT_LBUTTONUP:
            self.mouse_down = False
        elif event == cv2.EVENT_MOUSEMOVE and self.mouse_down:
            dx = x - self.last_mouse_x
            dy = y - self.last_mouse_y
            self.camera.rotation[0] += dx * 0.005  # Yaw
            self.camera.rotation[1] += dy * 0.005  # Pitch
            # Clamp pitch
            self.camera.rotation[1] = np.clip(self.camera.rotation[1], -np.pi/2 + 0.1, np.pi/2 - 0.1)
            self.last_mouse_x = x
            self.last_mouse_y = y
    
    def run(self):
        """Main viewer loop"""
        if not self.connect():
            return
        
        self.running = True
        
        # Create window
        window_name = "GPS-SLAM Viewer"
        cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
        cv2.setMouseCallback(window_name, self.mouse_callback)
        
        print("\n=== GPS-SLAM Viewer Controls ===")
        print("W/S - Move forward/backward")
        print("A/D - Strafe left/right")
        print("Q/E - Move up/down")
        print("Arrow keys - Rotate camera")
        print("Mouse drag - Look around")
        print("+/- - Adjust move speed")
        print("R - Reset camera")
        print("ESC - Quit")
        print("================================\n")
        
        frame_times = []
        
        try:
            while self.running:
                start_time = time.time()
                
                # Send camera pose
                self.send_camera_pose()
                
                # Receive rendered image
                img = self.receive_image()
                if img is None:
                    print("Failed to receive image, reconnecting...")
                    break
                
                # Receive additional data (must read all data server sends)
                self.receive_additional_data()
                
                # Calculate FPS
                frame_time = time.time() - start_time
                frame_times.append(frame_time)
                if len(frame_times) > 30:
                    frame_times.pop(0)
                self.fps = 1.0 / (sum(frame_times) / len(frame_times))
                
                # Draw FPS and info
                info_text = f"FPS: {self.fps:.1f} | Pos: ({self.camera.position[0]:.2f}, {self.camera.position[1]:.2f}, {self.camera.position[2]:.2f})"
                cv2.putText(img, info_text, (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
                
                # Display
                cv2.imshow(window_name, img)
                self.last_frame = img
                
                # Handle input (waitKey returns -1 if no key pressed)
                key = cv2.waitKey(1) & 0xFF
                if key == 27:  # ESC
                    self.running = False
                elif key != 255:
                    self.handle_input(key)
        
        except KeyboardInterrupt:
            print("\nInterrupted by user")
        except Exception as e:
            print(f"Error: {e}")
        finally:
            self.disconnect()
            cv2.destroyAllWindows()
            print("Viewer closed")


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="GPS-SLAM Viewer Client")
    parser.add_argument("--host", type=str, default="localhost", 
                        help="Server hostname or IP")
    parser.add_argument("--port", type=int, default=6688,
                        help="Server port (default: 6688)")
    parser.add_argument("--width", type=int, default=1200,
                        help="Render width (must match model config, default: 1200)")
    parser.add_argument("--height", type=int, default=680,
                        help="Render height (must match model config, default: 680)")
    
    args = parser.parse_args()
    
    client = GPSSLAMViewerClient(args.host, args.port)
    client.camera.width = args.width
    client.camera.height = args.height
    
    print(f"Connecting to GPS-SLAM server at {args.host}:{args.port}...")
    client.run()


if __name__ == "__main__":
    main()
