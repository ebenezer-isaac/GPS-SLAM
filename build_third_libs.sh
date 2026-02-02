#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "${SCRIPT_DIR}"

THIRDLIB_PATH=${THIRDLIB_PATH:-"${SCRIPT_DIR}/ThirdLibs"}
INSTALL_PATH=${INSTALL_PATH:-"${THIRDLIB_PATH}/install"}

if [ ! -d "${THIRDLIB_PATH}" ]; then
	echo "ThirdLibs directory not found at ${THIRDLIB_PATH}. Please extract ThirdLibs.zip." >&2
	exit 1
fi

CPU_COUNT=$(nproc)
if (( CPU_COUNT > 8 )); then
	DEFAULT_JOBS=8

elif (( CPU_COUNT < 1 )); then
	DEFAULT_JOBS=1
else

	DEFAULT_JOBS=${CPU_COUNT}
fi
JOBS=${JOBS:-${DEFAULT_JOBS}}

LOG_FILE=${LOG_FILE:-"${SCRIPT_DIR}/build_log.txt"}
echo "Logging to ${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "Using ${JOBS} parallel jobs"

build_component() {
	local name=$1
	local source_dir=$2
	shift 2 || true

	local cmake_flags=("$@")

	if [ ! -d "${source_dir}" ]; then
		echo "Missing ${name} source directory: ${source_dir}" >&2
		exit 1
	fi

	local build_dir="${source_dir}/build"
	echo "\n==== Building ${name} ===="
	cmake -S "${source_dir}" -B "${build_dir}" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="${INSTALL_PATH}" \
		"${cmake_flags[@]}"

	cmake --build "${build_dir}" -- -j"${JOBS}"
	cmake --install "${build_dir}"
}

build_component "assimp" "${THIRDLIB_PATH}/assimp" \
	-DASSIMP_BUILD_ASSIMP_TOOLS=OFF \
	-DASSIMP_BUILD_TESTS=OFF

build_component "freetype" "${THIRDLIB_PATH}/freetype" \
	-DBUILD_SHARED_LIBS=OFF

build_component "indicators" "${THIRDLIB_PATH}/indicators"

build_component "Pangolin" "${THIRDLIB_PATH}/Pangolin" \
	-DBUILD_PANGOLIN_PYTHON=OFF \
	-DBUILD_EXAMPLES=OFF \
	-DBUILD_TOOLS=ON \
	-DBUILD_TESTS=OFF

build_component "tensorboard_logger" "${THIRDLIB_PATH}/tensorboard_logger" \
	-DCMAKE_PREFIX_PATH="${INSTALL_PATH}"

build_component "tinyply" "${THIRDLIB_PATH}/tinyply" \
	-DBUILD_EXAMPLES=OFF

build_component "yaml-cpp" "${THIRDLIB_PATH}/yaml-cpp" \
	-DYAML_CPP_BUILD_TESTS=OFF \
	-DYAML_BUILD_SHARED_LIBS=OFF \
	-DYAML_CPP_BUILD_TOOLS=OFF

echo "\nAll third-party libraries built successfully!"