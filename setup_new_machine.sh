#!/usr/bin/env bash
###############################################################################
# GPS-SLAM Complete Setup Script
# 
# This script sets up GPS-SLAM on a new machine:
# 1. Downloads ThirdLibs.zip (required third-party libraries)
# 2. Downloads Replica dataset
# 3. Downloads GPS_SLAM Indoor dataset (optional)
# 4. Builds third-party libraries
# 5. Builds the main project
#
# Prerequisites:
#   - CUDA 12.x installed
#   - GCC 11.x installed
#   - cmake >= 3.22
#   - wget, unzip, python3
#   - OpenGL development libraries
#
# Usage:
#   chmod +x setup_new_machine.sh
#   ./setup_new_machine.sh [options]
#
# Options:
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

# Default options
SKIP_THIRDLIBS=false
SKIP_REPLICA=false
SKIP_GPSSLAM=false
SKIP_BUILD=false
THIRDLIBS_ONLY=false
DATA_ONLY=false
BUILD_ONLY=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=()
    
    command -v cmake >/dev/null 2>&1 || missing+=("cmake")
    command -v make >/dev/null 2>&1 || missing+=("make")
    command -v wget >/dev/null 2>&1 || missing+=("wget")
    command -v unzip >/dev/null 2>&1 || missing+=("unzip")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    command -v nvcc >/dev/null 2>&1 || missing+=("cuda (nvcc)")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing prerequisites: ${missing[*]}"
        log_info "Please install them before running this script"
        exit 1
    fi
    
    # Check GCC version
    GCC_VERSION=$(gcc -dumpversion | cut -d. -f1)
    if [[ $GCC_VERSION -lt 11 ]]; then
        log_warn "GCC version $GCC_VERSION detected. GCC 11+ recommended."
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
