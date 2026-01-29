#!/usr/bin/env bash
###############################################################################
# GPS-SLAM Complete Setup Script
# 
# This script sets up GPS-SLAM on a new machine:
# 1. Auto-configures CUDA and environment (supports UCL CS machines)
# 2. Downloads ThirdLibs.zip (required third-party libraries)
# 3. Downloads Replica dataset
# 4. Downloads GPS_SLAM Indoor dataset (optional)
# 5. Builds third-party libraries
# 6. Builds the main project
#
# Tested on:
#   - UCL CS Remote Workstations (RTX 4090, CUDA in /opt/cuda/)
#   - Ubuntu 20.04/22.04/24.04 with sudo access
#
# Usage:
#   chmod +x setup_new_machine.sh
#   ./setup_new_machine.sh [options]
#
# Options:
#   --install-prereqs    Install system prerequisites (apt packages, GCC 11)
#   --install-cuda       Install CUDA 12.4 (requires sudo, reboot after)
#   --skip-thirdlibs     Skip downloading ThirdLibs.zip
#   --skip-replica       Skip downloading Replica dataset
#   --skip-gpsslam       Skip downloading GPS_SLAM Indoor dataset
#   --skip-build         Skip building (just download files)
#   --thirdlibs-only     Only download and extract ThirdLibs
#   --data-only          Only download datasets
#   --build-only         Only build (assumes files are present)
#   --help               Show this help message
#
###############################################################################
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "${SCRIPT_DIR}"

###############################################################################
# AUTO-CONFIGURE ENVIRONMENT (UCL CS Machines & common setups)
###############################################################################
auto_configure_environment() {
    echo -e "${BLUE}[INFO]${NC} Auto-configuring environment..."
    
    # UCL CS machines: CUDA is in /opt/cuda/cuda-X.X/
    if [[ -d "/opt/cuda" ]]; then
        # Find available CUDA versions, prefer 12.4
        if [[ -d "/opt/cuda/cuda-12.4" ]]; then
            CUDA_HOME="/opt/cuda/cuda-12.4"
        else
            # Use latest available
            CUDA_HOME=$(ls -d /opt/cuda/cuda-* 2>/dev/null | sort -V | tail -1)
        fi
        
        if [[ -n "$CUDA_HOME" ]] && [[ -f "$CUDA_HOME/bin/nvcc" ]]; then
            export PATH="$CUDA_HOME/bin:$PATH"
            export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
            export CUDA_HOME="$CUDA_HOME"
            echo -e "${GREEN}[SUCCESS]${NC} Configured CUDA from $CUDA_HOME"
        fi
    fi
    
    # Standard CUDA location: /usr/local/cuda
    if ! command -v nvcc >/dev/null 2>&1; then
        if [[ -d "/usr/local/cuda" ]]; then
            export PATH="/usr/local/cuda/bin:$PATH"
            export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
            export CUDA_HOME="/usr/local/cuda"
            echo -e "${GREEN}[SUCCESS]${NC} Configured CUDA from /usr/local/cuda"
        fi
    fi
    
    # Add user local bin to PATH (for pip packages like gdown)
    if [[ -d "$HOME/.local/bin" ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

# Run auto-configure immediately
auto_configure_environment

# Default options
SKIP_THIRDLIBS=false
SKIP_REPLICA=false
SKIP_GPSSLAM=false
SKIP_BUILD=false
THIRDLIBS_ONLY=false
DATA_ONLY=false
BUILD_ONLY=false
INSTALL_PREREQS=false
INSTALL_CUDA=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install-prereqs)
            INSTALL_PREREQS=true
            shift
            ;;
        --install-cuda)
            INSTALL_CUDA=true
            shift
            ;;
        --skip-thirdlibs)
            SKIP_THIRDLIBS=true
            shift
            ;;
        --skip-replica)
            SKIP_REPLICA=true
            shift
            ;;
        --skip-gpsslam)
            SKIP_GPSSLAM=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --thirdlibs-only)
            THIRDLIBS_ONLY=true
            shift
            ;;
        --data-only)
            DATA_ONLY=true
            shift
            ;;
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --help)
            head -40 "$0" | tail -35
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Install prerequisites in user space (no sudo required)
install_prerequisites_user() {
    log_info "=== User-Space Installation (No Root) ==="
    
    # Create local install directory
    local LOCAL_DIR="${HOME}/.local"
    mkdir -p "${LOCAL_DIR}/bin" "${LOCAL_DIR}/lib" "${LOCAL_DIR}/include"
    
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":${LOCAL_DIR}/bin:"* ]]; then
        export PATH="${LOCAL_DIR}/bin:$PATH"
    fi
    
    # Update bashrc with all needed environment variables
    log_info "Updating ~/.bashrc with environment configuration..."
    
    # Remove old GPS-SLAM config if exists
    sed -i '/# GPS-SLAM Environment/,/# END GPS-SLAM/d' ~/.bashrc 2>/dev/null || true
    
    # Add new config block
    cat >> ~/.bashrc << 'BASHRC_CONFIG'

# GPS-SLAM Environment (auto-generated)
export PATH="${HOME}/.local/bin:$PATH"

# CUDA Configuration (UCL CS machines)
if [[ -d "/opt/cuda/cuda-12.4" ]]; then
    export CUDA_HOME="/opt/cuda/cuda-12.4"
    export PATH="$CUDA_HOME/bin:$PATH"
    export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
elif [[ -d "/usr/local/cuda" ]]; then
    export CUDA_HOME="/usr/local/cuda"
    export PATH="$CUDA_HOME/bin:$PATH"
    export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
fi
# END GPS-SLAM
BASHRC_CONFIG
    
    log_success "~/.bashrc updated with CUDA configuration"
    
    # Install pip packages in user space
    if command -v pip3 >/dev/null 2>&1; then
        log_info "Installing Python packages (gdown, numpy, pillow)..."
        pip3 install --user --quiet gdown numpy pillow || pip3 install --user gdown numpy pillow
        log_success "Python packages installed"
    elif command -v pip >/dev/null 2>&1; then
        pip install --user --quiet gdown numpy pillow || pip install --user gdown numpy pillow
    fi
    
    log_success "User-space setup complete"
}

# Install system prerequisites
install_prerequisites() {
    log_info "=== Installing System Prerequisites ==="
    
    # Check if we have sudo access
    if ! command -v sudo >/dev/null 2>&1 || ! sudo -n true 2>/dev/null; then
        log_warn "No sudo access detected. Attempting user-space installation..."
        install_prerequisites_user
        return $?
    fi
    
    sudo apt update
    
    # Essential build tools
    sudo apt install -y \
        build-essential \
        cmake \
        git \
        wget \
        curl \
        unzip \
        pkg-config \
        ninja-build
    
    # Python
    sudo apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev
    
    # OpenGL and graphics libraries
    sudo apt install -y \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        libglew-dev \
        libglfw3-dev \
        freeglut3-dev \
        libxrandr-dev \
        libxinerama-dev \
        libxcursor-dev \
        libxi-dev \
        libxxf86vm-dev
    
    # Image and other libraries
    sudo apt install -y \
        libjpeg-dev \
        libpng-dev \
        libtiff-dev \
        libavcodec-dev \
        libavformat-dev \
        libswscale-dev \
        libv4l-dev \
        libdc1394-dev \
        libeigen3-dev
    
    # Install GCC 11 (required for CUDA compatibility)
    log_info "Installing GCC 11..."
    sudo apt install -y gcc-11 g++-11
    
    # Set GCC 11 as default
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 110 \
        --slave /usr/bin/g++ g++ /usr/bin/g++-11 \
        --slave /usr/bin/gcov gcov /usr/bin/gcov-11
    
    # Install gdown for Google Drive downloads
    pip3 install --user gdown
    
    log_success "System prerequisites installed"
    log_info "GCC version: $(gcc --version | head -1)"
}

# Install CUDA 12.4
install_cuda() {
    log_info "=== Installing CUDA 12.4 ==="
    
    if command -v nvcc >/dev/null 2>&1; then
        local cuda_version=$(nvcc --version | grep "release" | awk '{print $6}' | cut -d',' -f1)
        log_warn "CUDA already installed: $cuda_version"
        read -p "Do you want to reinstall? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    # Detect Ubuntu version
    local ubuntu_version=$(lsb_release -rs)
    local ubuntu_codename=$(lsb_release -cs)
    log_info "Detected Ubuntu $ubuntu_version ($ubuntu_codename)"
    
    # Determine the correct package
    local cuda_repo_pkg=""
    case $ubuntu_version in
        24.04)
            cuda_repo_pkg="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb"
            ;;
        22.04)
            cuda_repo_pkg="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb"
            ;;
        20.04)
            cuda_repo_pkg="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.1-1_all.deb"
            ;;
        *)
            log_error "Unsupported Ubuntu version: $ubuntu_version"
            log_info "Please install CUDA manually from: https://developer.nvidia.com/cuda-downloads"
            return 1
            ;;
    esac
    
    log_info "Downloading CUDA keyring..."
    wget -O /tmp/cuda-keyring.deb "$cuda_repo_pkg"
    sudo dpkg -i /tmp/cuda-keyring.deb
    sudo apt update
    
    log_info "Installing CUDA 12.4..."
    sudo apt install -y cuda-toolkit-12-4
    
    # Add CUDA to PATH
    log_info "Configuring environment variables..."
    
    local cuda_env_script="/etc/profile.d/cuda.sh"
    echo 'export PATH=/usr/local/cuda-12.4/bin:$PATH' | sudo tee "$cuda_env_script"
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.4/lib64:$LD_LIBRARY_PATH' | sudo tee -a "$cuda_env_script"
    
    # Also add to user's bashrc
    if ! grep -q "cuda-12.4" ~/.bashrc; then
        echo '' >> ~/.bashrc
        echo '# CUDA 12.4' >> ~/.bashrc
        echo 'export PATH=/usr/local/cuda-12.4/bin:$PATH' >> ~/.bashrc
        echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.4/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
    fi
    
    # Source for current session
    export PATH=/usr/local/cuda-12.4/bin:$PATH
    export LD_LIBRARY_PATH=/usr/local/cuda-12.4/lib64:$LD_LIBRARY_PATH
    
    log_success "CUDA 12.4 installed"
    log_warn "Please run 'source ~/.bashrc' or log out and back in to update your PATH"
    log_info "Then run this script again without --install-cuda to continue setup"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=()
    local warnings=()
    
    command -v cmake >/dev/null 2>&1 || missing+=("cmake")
    command -v make >/dev/null 2>&1 || missing+=("make")
    command -v wget >/dev/null 2>&1 || { command -v curl >/dev/null 2>&1 || missing+=("wget or curl"); }
    command -v unzip >/dev/null 2>&1 || missing+=("unzip")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    command -v nvcc >/dev/null 2>&1 || missing+=("cuda (nvcc)")
    command -v gcc >/dev/null 2>&1 || missing+=("gcc")
    command -v g++ >/dev/null 2>&1 || missing+=("g++")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing prerequisites: ${missing[*]}"
        echo ""
        
        # Check for module system
        if command -v module >/dev/null 2>&1; then
            log_info "Module system detected. Try loading required modules:"
            echo ""
            echo "  module avail                    # List all available modules"
            echo "  module load cuda                # Load CUDA"
            echo "  module load gcc/11              # Load GCC 11"
            echo "  module load cmake               # Load CMake"
            echo "  module load python              # Load Python"
            echo ""
            echo "After loading modules, run this script again."
            echo ""
        else
            log_info "Please install them before running this script"
            log_info "Or run: ./setup_new_machine.sh --install-prereqs"
        fi
        exit 1
    fi
    
    # Check GCC version
    GCC_VERSION=$(gcc -dumpversion | cut -d. -f1)
    if [[ $GCC_VERSION -lt 11 ]]; then
        log_warn "GCC version $GCC_VERSION detected. GCC 11+ recommended."
        log_info "Try: module load gcc/11 (if on a cluster)"
    fi
    
    # Show CUDA version
    if command -v nvcc >/dev/null 2>&1; then
        log_info "CUDA: $(nvcc --version | grep release | awk '{print $5}' | tr -d ',')"
    fi
    
    log_success "All prerequisites satisfied"
}

# Download with retry and progress
download_file() {
    local url=$1
    local output=$2
    local description=$3
    
    if [[ -f "$output" ]]; then
        log_info "$description already exists, skipping download"
        return 0
    fi
    
    log_info "Downloading $description..."
    local max_retries=3
    local retry=0
    
    while [[ $retry -lt $max_retries ]]; do
        if wget -c --show-progress -O "$output" "$url"; then
            log_success "Downloaded $description"
            return 0
        fi
        retry=$((retry + 1))
        log_warn "Download failed, retry $retry/$max_retries..."
        sleep 5
    done
    
    log_error "Failed to download $description after $max_retries attempts"
    return 1
}

# Download from Google Drive (for larger files)
download_gdrive() {
    local file_id=$1
    local output=$2
    local description=$3
    
    if [[ -f "$output" ]]; then
        log_info "$description already exists, skipping download"
        return 0
    fi
    
    log_info "Downloading $description from Google Drive..."
    
    # Check if gdown is available
    if command -v gdown >/dev/null 2>&1; then
        gdown "https://drive.google.com/uc?id=$file_id" -O "$output"
    else
        log_warn "gdown not found. Installing via pip..."
        pip3 install --user gdown
        ~/.local/bin/gdown "https://drive.google.com/uc?id=$file_id" -O "$output" || gdown "https://drive.google.com/uc?id=$file_id" -O "$output"
    fi
    
    if [[ -f "$output" ]]; then
        log_success "Downloaded $description"
        return 0
    else
        log_error "Failed to download $description"
        return 1
    fi
}

# Download ThirdLibs
download_thirdlibs() {
    log_info "=== Downloading ThirdLibs ==="
    
    local thirdlibs_zip="${SCRIPT_DIR}/ThirdLibs.zip"
    local thirdlibs_dir="${SCRIPT_DIR}/ThirdLibs"
    
    # Google Drive file ID for ThirdLibs.zip
    # From: https://drive.google.com/file/d/1yD0wK8tX4FMos8Fk6-AIxeLdZ5AVuwCO/view?usp=sharing
    local gdrive_id="1yD0wK8tX4FMos8Fk6-AIxeLdZ5AVuwCO"
    
    if [[ -d "$thirdlibs_dir" ]] && [[ -d "$thirdlibs_dir/assimp" ]]; then
        log_info "ThirdLibs directory already exists and appears complete"
        return 0
    fi
    
    download_gdrive "$gdrive_id" "$thirdlibs_zip" "ThirdLibs.zip"
    
    log_info "Extracting ThirdLibs.zip..."
    unzip -o "$thirdlibs_zip" -d "${SCRIPT_DIR}"
    log_success "ThirdLibs extracted"
}

# Download Replica dataset
download_replica() {
    log_info "=== Downloading Replica Dataset ==="
    
    mkdir -p "${SCRIPT_DIR}/data"
    cd "${SCRIPT_DIR}/data"
    
    # Download main Replica dataset
    if [[ ! -d "Replica_raw" ]]; then
        if [[ ! -f "Replica.zip" ]]; then
            download_file \
                "https://cvg-data.inf.ethz.ch/nice-slam/data/Replica.zip" \
                "Replica.zip" \
                "Replica.zip"
        fi
        
        log_info "Extracting Replica.zip..."
        unzip -o Replica.zip
        mv Replica Replica_raw
        log_success "Replica dataset extracted"
    else
        log_info "Replica_raw already exists, skipping"
    fi
    
    # Download culled mesh
    if [[ ! -d "cull_replica_mesh" ]]; then
        if [[ ! -f "cull_replica_mesh.zip" ]]; then
            download_file \
                "https://cvg-data.inf.ethz.ch/nice-slam/cull_replica_mesh.zip" \
                "cull_replica_mesh.zip" \
                "cull_replica_mesh.zip"
        fi
        
        log_info "Extracting cull_replica_mesh.zip..."
        unzip -o cull_replica_mesh.zip
        log_success "Culled mesh extracted"
    else
        log_info "cull_replica_mesh already exists, skipping"
    fi
    
    cd "${SCRIPT_DIR}"
}

# Download GPS_SLAM Indoor dataset
download_gpsslam_indoor() {
    log_info "=== Downloading GPS_SLAM Indoor Dataset ==="
    
    mkdir -p "${SCRIPT_DIR}/data"
    cd "${SCRIPT_DIR}/data"
    
    # Google Drive file ID for GPS_SLAM Indoor dataset
    # From: https://drive.google.com/file/d/1ZVICqHVdWDO1OvltxGJXuJ2YG4FYNLHD/view?usp=sharing
    local gdrive_id="1ZVICqHVdWDO1OvltxGJXuJ2YG4FYNLHD"
    
    if [[ -d "gps_slam" ]] && [[ -n "$(ls -A gps_slam 2>/dev/null)" ]]; then
        log_info "gps_slam directory already exists and is not empty"
        cd "${SCRIPT_DIR}"
        return 0
    fi
    
    download_gdrive "$gdrive_id" "gps_slam_indoor.zip" "GPS_SLAM Indoor dataset"
    
    log_info "Extracting GPS_SLAM Indoor dataset..."
    unzip -o gps_slam_indoor.zip
    log_success "GPS_SLAM Indoor dataset extracted"
    
    cd "${SCRIPT_DIR}"
}

# Preprocess Replica dataset
preprocess_replica() {
    log_info "=== Preprocessing Replica Dataset ==="
    
    if [[ ! -d "${SCRIPT_DIR}/data/Replica_raw" ]]; then
        log_error "Replica_raw not found. Please download Replica first."
        return 1
    fi
    
    if [[ -d "${SCRIPT_DIR}/data/replica" ]] && [[ -n "$(ls -A ${SCRIPT_DIR}/data/replica 2>/dev/null)" ]]; then
        log_info "data/replica already exists, skipping preprocessing"
        return 0
    fi
    
    log_info "Running replica_preprocess.py..."
    python3 scripts/replica_preprocess.py \
        --input-root data/Replica_raw \
        --output-root data/replica \
        --frame-count 2000 \
        --overwrite
    
    log_success "Replica preprocessing complete"
}

# Build third-party libraries
build_thirdlibs() {
    log_info "=== Building Third-Party Libraries ==="
    
    if [[ ! -d "${SCRIPT_DIR}/ThirdLibs" ]]; then
        log_error "ThirdLibs directory not found. Please download ThirdLibs first."
        return 1
    fi
    
    if [[ -d "${SCRIPT_DIR}/ThirdLibs/install/lib" ]]; then
        log_info "ThirdLibs appear to be already built, skipping"
        log_info "Delete ThirdLibs/install to force rebuild"
        return 0
    fi
    
    bash "${SCRIPT_DIR}/build_third_libs.sh"
    log_success "Third-party libraries built"
}

# Build main project
build_project() {
    log_info "=== Building GPS-SLAM ==="
    
    mkdir -p "${SCRIPT_DIR}/build"
    cd "${SCRIPT_DIR}/build"
    
    log_info "Running cmake..."
    cmake ..
    
    # Determine number of jobs
    local jobs=$(nproc)
    if [[ $jobs -gt 16 ]]; then
        jobs=16
    fi
    
    log_info "Building with $jobs parallel jobs..."
    make -j"$jobs"
    
    cd "${SCRIPT_DIR}"
    log_success "GPS-SLAM built successfully"
}

# Main execution
main() {
    echo "=========================================="
    echo "  GPS-SLAM Complete Setup Script"
    echo "=========================================="
    echo ""
    
    # Handle prerequisite installation first
    if [[ "$INSTALL_PREREQS" == true ]]; then
        install_prerequisites
    fi
    
    if [[ "$INSTALL_CUDA" == true ]]; then
        install_cuda
        echo ""
        log_info "CUDA installation complete. Please run:"
        echo "  source ~/.bashrc"
        echo "  ./setup_new_machine.sh"
        exit 0
    fi
    
    check_prerequisites
    
    if [[ "$BUILD_ONLY" == true ]]; then
        build_thirdlibs
        build_project
        log_success "Build complete!"
        exit 0
    fi
    
    if [[ "$DATA_ONLY" == true ]]; then
        download_replica
        preprocess_replica
        if [[ "$SKIP_GPSSLAM" != true ]]; then
            download_gpsslam_indoor
        fi
        log_success "Data download complete!"
        exit 0
    fi
    
    if [[ "$THIRDLIBS_ONLY" == true ]]; then
        download_thirdlibs
        build_thirdlibs
        log_success "ThirdLibs setup complete!"
        exit 0
    fi
    
    # Full setup
    if [[ "$SKIP_THIRDLIBS" != true ]]; then
        download_thirdlibs
    fi
    
    if [[ "$SKIP_REPLICA" != true ]]; then
        download_replica
        preprocess_replica
    fi
    
    if [[ "$SKIP_GPSSLAM" != true ]]; then
        download_gpsslam_indoor
    fi
    
    if [[ "$SKIP_BUILD" != true ]]; then
        build_thirdlibs
        build_project
    fi
    
    echo ""
    echo "=========================================="
    log_success "GPS-SLAM setup complete!"
    echo "=========================================="
    echo ""
    echo "To run GPS-SLAM:"
    echo "  ./build/slam_trainer configs/release/replica/office0.yaml"
    echo ""
    echo "For evaluation:"
    echo "  python scripts/metric_general.py --gt_path data/replica/office0 --render_path output/release/replica/office0/val/render"
    echo ""
}

main "$@"
