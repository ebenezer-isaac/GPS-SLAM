# Quick Start Guide for New Machine Setup

This guide helps you set up GPS-SLAM on a new machine from your forked repository.

## Prerequisites

Before running the setup, ensure you have:

- **Ubuntu 20.04/22.04/24.04** (tested on 24.04)
- **CUDA 12.x** installed with `nvcc` in PATH
- **GCC 11.x** (for CUDA compatibility)
- **CMake 3.22+**
- **Python 3.8+** with pip
- **System packages:**
  ```bash
  sudo apt update
  sudo apt install -y build-essential cmake git wget unzip \
      libgl1-mesa-dev libglu1-mesa-dev libglew-dev \
      libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev \
      python3 python3-pip python3-venv
  ```

## Step 1: Clone Your Fork

```bash
git clone --recursive https://github.com/YOUR_USERNAME/GPS-SLAM.git
cd GPS-SLAM
git checkout your-branch-name  # if using a specific branch
```

## Step 2: Run the Setup Script

The setup script handles everything automatically:

```bash
chmod +x setup_new_machine.sh
./setup_new_machine.sh
```

This will:
1. Download ThirdLibs.zip (~2GB) from Google Drive
2. Download Replica dataset (~5GB) from ETH Zurich
3. Download GPS_SLAM Indoor dataset (~1GB) from Google Drive
4. Build all third-party libraries
5. Build the main GPS-SLAM project

### Setup Options

```bash
# Skip specific downloads
./setup_new_machine.sh --skip-gpsslam     # Skip GPS_SLAM Indoor dataset
./setup_new_machine.sh --skip-replica     # Skip Replica dataset

# Partial setup
./setup_new_machine.sh --thirdlibs-only   # Only setup ThirdLibs
./setup_new_machine.sh --data-only        # Only download datasets
./setup_new_machine.sh --build-only       # Only build (files must exist)

# Skip build (just download)
./setup_new_machine.sh --skip-build
```

## Step 3: Verify Installation

```bash
# Check if build succeeded
ls -la build/slam_trainer

# Run a quick test
./build/slam_trainer configs/release/replica/office0.yaml
```

## Manual Setup (Alternative)

If the automated script doesn't work, follow these steps:

### 1. Download ThirdLibs

From [Google Drive](https://drive.google.com/file/d/1yD0wK8tX4FMos8Fk6-AIxeLdZ5AVuwCO/view?usp=sharing) or [BaiduNetDisk](https://pan.baidu.com/s/1zkN2GSNSQdArECPC1x_cWQ?pwd=2hei)

```bash
# Using gdown (install with: pip install gdown)
gdown "https://drive.google.com/uc?id=1yD0wK8tX4FMos8Fk6-AIxeLdZ5AVuwCO" -O ThirdLibs.zip
unzip ThirdLibs.zip
```

### 2. Build ThirdLibs

```bash
bash build_third_libs.sh
```

### 3. Download Datasets

```bash
# Replica dataset
bash download_replica.sh

# Preprocess Replica
python3 scripts/replica_preprocess.py \
    --input-root data/Replica_raw \
    --output-root data/replica \
    --frame-count 2000 --overwrite

# GPS_SLAM Indoor (optional)
gdown "https://drive.google.com/uc?id=1ZVICqHVdWDO1OvltxGJXuJ2YG4FYNLHD" -O data/gps_slam_indoor.zip
cd data && unzip gps_slam_indoor.zip && cd ..
```

### 4. Build GPS-SLAM

```bash
mkdir -p build && cd build
cmake ..
make -j$(nproc)
```

## Troubleshooting

### CUDA not found
```bash
# Add CUDA to PATH
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
```

### GCC version mismatch
```bash
# Install GCC 11
sudo apt install gcc-11 g++-11
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 100
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 100
```

### gdown quota exceeded
If Google Drive quota is exceeded, try:
1. Download manually from the browser
2. Use BaiduNetDisk links (requires Baidu account)
3. Wait a few hours and try again

### OpenGL errors
```bash
sudo apt install libgl1-mesa-dev libglu1-mesa-dev freeglut3-dev
```

## Download Links Summary

| File | Size | Google Drive | BaiduNetDisk |
|------|------|--------------|--------------|
| ThirdLibs.zip | ~2GB | [Link](https://drive.google.com/file/d/1yD0wK8tX4FMos8Fk6-AIxeLdZ5AVuwCO/view) | [Link](https://pan.baidu.com/s/1zkN2GSNSQdArECPC1x_cWQ?pwd=2hei) |
| GPS_SLAM Indoor | ~1GB | [Link](https://drive.google.com/file/d/1ZVICqHVdWDO1OvltxGJXuJ2YG4FYNLHD/view) | [Link](https://pan.baidu.com/s/1YHZn6B781D9ZtFsf0fi9sw?pwd=5964) |
| Replica.zip | ~5GB | [ETH Link](https://cvg-data.inf.ethz.ch/nice-slam/data/Replica.zip) | - |
| cull_replica_mesh.zip | ~50MB | [ETH Link](https://cvg-data.inf.ethz.ch/nice-slam/cull_replica_mesh.zip) | - |
