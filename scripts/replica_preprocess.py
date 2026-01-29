import argparse
import glob
import math
import os
import re
import shutil
from pathlib import Path
from typing import List, Optional

import numpy as np


def generate_dir(path: Path, overwrite: bool = False):
    """Create a clean output directory for a scene."""

    if path.exists():
        if not overwrite:
            raise FileExistsError(f"{path} already exists. Use --overwrite to replace it.")
        shutil.rmtree(path)

    path.mkdir(parents=True, exist_ok=True)
    (path / "camera").mkdir(exist_ok=True)


def get_color_images(src_dir, dst_dir):
    if not os.path.exists(dst_dir):
        os.makedirs(dst_dir)

    pattern = re.compile(r'^frame\d{6}\.jpg$')
    img_count = 0
    for filename in os.listdir(src_dir):
        if pattern.match(filename):
            src_path = os.path.join(src_dir, filename)
            dst_path = os.path.join(dst_dir, filename)

            shutil.copy2(src_path, dst_path)
            img_count += 1

    print("color finish, count: {}".format(img_count))

def get_depths(src_dir, dst_dir):
    if not os.path.exists(dst_dir):
        os.makedirs(dst_dir)

    pattern = re.compile(r'^depth\d{6}\.png$')
    img_count = 0
    for filename in os.listdir(src_dir):
        if pattern.match(filename):
            src_path = os.path.join(src_dir, filename)
            dst_path = os.path.join(dst_dir, filename)

            shutil.copy2(src_path, dst_path)
            img_count += 1

    print("color finish, count: {}".format(img_count))

def get_intrinsics(fx, fy, cx, cy):
    return np.array([[fx, 0, cx], [0, fy, cy], [0, 0, 1]])


def get_color_extrinsics(traj_path, save_dir):
    raw_traj = np.loadtxt(traj_path)
    raw_traj = raw_traj.reshape((raw_traj.shape[0], 4, 4))
    pose_count = 0
    for i, matrix in enumerate(raw_traj):
        filename = save_dir + f"/pose{str(i).zfill(6)}.txt"
        np.savetxt(filename, matrix, fmt='%.8f')
        pose_count += 1
    print("pose finish, count: {}".format(pose_count))
    return raw_traj


def sample_and_rename_poses(input_dir, sample_interval=10):
    pose_files = sorted(glob.glob(os.path.join(input_dir, "pose*.txt")))
    total_poses = len(pose_files)
    
    sampled_count = (total_poses + sample_interval - 1) // sample_interval
    
    print(f"Total poses: {total_poses}")
    print(f"After sampling: {sampled_count}")
    
    temp_dir = os.path.join(input_dir, "temp")
    os.makedirs(temp_dir, exist_ok=True)
    
    new_idx = 0
    for i in range(0, total_poses, sample_interval):
        if i >= total_poses:
            break
            
        src_file = pose_files[i]
        dst_file = os.path.join(temp_dir, f"pose{new_idx:06d}.txt")
        
        with open(src_file, 'r') as f_src:
            content = f_src.read()
        with open(dst_file, 'w') as f_dst:
            f_dst.write(content)
            
        new_idx += 1
    
    for pose_file in pose_files:
        os.remove(pose_file)
    
    sampled_files = glob.glob(os.path.join(temp_dir, "pose*.txt"))
    for sampled_file in sampled_files:
        filename = os.path.basename(sampled_file)
        os.rename(sampled_file, os.path.join(input_dir, filename))
    
    os.rmdir(temp_dir)
    
    print("Sampling and renaming completed!")


def sample_and_rename_frames(input_dir, sample_interval=10):
    frame_files = sorted(glob.glob(os.path.join(input_dir, "frame*.jpg")))
    total_frames = len(frame_files)
    
    sampled_count = (total_frames + sample_interval - 1) // sample_interval
    
    print(f"Total frames: {total_frames}")
    print(f"After sampling: {sampled_count}")
    
    temp_dir = os.path.join(input_dir, "temp")
    os.makedirs(temp_dir, exist_ok=True)
    
    new_idx = 0
    for i in range(0, total_frames, sample_interval):
        if i >= total_frames:
            break
            
        src_file = frame_files[i]
        dst_file = os.path.join(temp_dir, f"frame{new_idx:06d}.jpg")
        
        shutil.copy2(src_file, dst_file)
        new_idx += 1
    
    for frame_file in frame_files:
        os.remove(frame_file)
    
    sampled_files = glob.glob(os.path.join(temp_dir, "frame*.jpg"))
    for sampled_file in sampled_files:
        filename = os.path.basename(sampled_file)
        os.rename(sampled_file, os.path.join(input_dir, filename))
    
    os.rmdir(temp_dir)
    print("Sampling and renaming completed!")

def sample_and_rename_depths(input_dir, sample_interval=10):
    frame_files = sorted(glob.glob(os.path.join(input_dir, "depth*.png")))
    total_frames = len(frame_files)
    
    sampled_count = (total_frames + sample_interval - 1) // sample_interval
    
    print(f"Total frames: {total_frames}")
    print(f"After sampling: {sampled_count}")
    
    temp_dir = os.path.join(input_dir, "temp")
    os.makedirs(temp_dir, exist_ok=True)
    
    new_idx = 0
    for i in range(0, total_frames, sample_interval):
        if i >= total_frames:
            break
            
        src_file = frame_files[i]
        dst_file = os.path.join(temp_dir, f"depth{new_idx:06d}.png")
        
        shutil.copy2(src_file, dst_file)
        new_idx += 1
    
    for frame_file in frame_files:
        os.remove(frame_file)
    
    sampled_files = glob.glob(os.path.join(temp_dir, "depth*.png"))
    for sampled_file in sampled_files:
        filename = os.path.basename(sampled_file)
        os.rename(sampled_file, os.path.join(input_dir, filename))
    
    os.rmdir(temp_dir)
    
    print("Sampling and renaming completed!")


def compute_sample_interval(frame_num: int, target_frames: Optional[int]) -> int:
    if not target_frames or frame_num <= target_frames:
        return 1
    return max(1, math.ceil(frame_num / target_frames))


def process_scene(scene: str, input_root: Path, output_root: Path, target_frames: int, overwrite: bool):
    fx = 600
    fy = 600
    cx = 599.5
    cy = 339.5
    w = 1200
    h = 680

    input_dir = input_root / scene
    output_dir = output_root / scene

    if not input_dir.exists():
        print(f"[skip] {input_dir} does not exist")
        return False

    traj_path = input_dir / "traj.txt"
    results_dir = input_dir / "results"

    if not traj_path.exists() or not results_dir.exists():
        print(f"[skip] {scene}: missing traj.txt or results directory")
        return False

    print(f"[process] {scene}")
    generate_dir(output_dir, overwrite=overwrite)

    camera_dir = output_dir / "camera"
    depth_dir = output_dir / "depth"

    color_poses = get_color_extrinsics(str(traj_path), str(camera_dir))
    frame_num = color_poses.shape[0]

    get_color_images(str(results_dir), str(camera_dir))
    get_depths(str(results_dir), str(depth_dir))

    intrinsics = get_intrinsics(fx, fy, cx, cy)
    np.savetxt(camera_dir / "intrinsics.txt", intrinsics, fmt="%.8f")
    img_shape = np.array([w, h], dtype=np.int32)
    np.savetxt(camera_dir / "img_shape.txt", img_shape, fmt="%d")

    interval = compute_sample_interval(frame_num, target_frames)
    if interval > 1:
        print(f"Sampling {scene} every {interval} frames to approach {target_frames} frames")
        sample_and_rename_poses(camera_dir, interval)
        sample_and_rename_frames(camera_dir, interval)
        sample_and_rename_depths(depth_dir, interval)

    print(f"[done] {scene}\n")
    return True


def collect_scenes(input_root: Path, requested: Optional[List[str]]) -> List[str]:
    if requested:
        return requested

    scenes = [p.name for p in sorted(input_root.iterdir()) if p.is_dir() and not p.name.startswith(".")]
    return scenes


def main():
    parser = argparse.ArgumentParser(description="Convert Replica raw data into GPS-SLAM format")
    parser.add_argument("--input-root", type=Path, default=Path("data/Replica_raw"), help="Location of raw Replica scenes")
    parser.add_argument("--output-root", type=Path, default=Path("data/replica"), help="Destination folder for converted scenes")
    parser.add_argument(
        "--scenes",
        nargs="*",
        help="Specific scene names to process (default: all subdirectories under input-root)",
    )
    parser.add_argument(
        "--frame-count",
        type=int,
        default=2000,
        help="Approximate number of frames to keep per scene (set <=0 to keep all frames)",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Allow replacing existing processed scenes",
    )

    args = parser.parse_args()
    target_frames = args.frame_count if args.frame_count and args.frame_count > 0 else None

    scenes = collect_scenes(args.input_root, args.scenes)
    if not scenes:
        print("No scenes found to process.")
        return

    args.output_root.mkdir(parents=True, exist_ok=True)

    processed = 0
    for scene in scenes:
        success = process_scene(scene, args.input_root, args.output_root, target_frames, args.overwrite)
        if success:
            processed += 1

    print(f"Processed {processed} / {len(scenes)} scenes.")


if __name__ == "__main__":
    main()
