#!/bin/bash

set -euo pipefail

TOOLCHAIN_TARBALL_URL="https://toolchains.bootlin.com/downloads/releases/toolchains/x86-64/tarballs/x86-64--glibc--stable-2025.08-1.tar.xz"
TOOLCHAIN_TARBALL="x86-64--glibc--stable-2025.08-1.tar.xz"
TOOLCHAIN_DIR=${TOOLCHAIN_DIR:-"/opt/toolchain"}
TARGET_BUILD_DIR=${TARGET_BUILD_DIR:-"/opt/target-build"}

extract_file() {
	local archive_file=$1
	local dest_dir=$2

	# Use environment variables with defaults
	local strip_components=${EXTRACT_FILE_STRIP_COMPONENTS:-0}
	local verbose=${EXTRACT_FILE_VERBOSE_EXTRACT:-false}

	# Make sure the archive file exists, if not find another archive file with a different extension.
	if [ ! -f "${archive_file}" ]; then
		msg "Archive file ${archive_file} does not exist, searching for alternative..."
		archive_file=$(find "${SOURCES}" -name "$(basename "${archive_file}" | sed 's/\.[^.]*$//').*" | head -1)
		if [ ! -f "${archive_file}" ]; then
			msg "Error: Archive file ${archive_file} does not exist."
			exit 1
		fi
		msg "Found alternative archive file: ${archive_file}"
	fi

	mkdir -vp "${dest_dir}"

	msg "Extracting to ${dest_dir}..."

	local verbose_flag=""
	if [ "${verbose}" = true ] || [ "${verbose}" = "true" ]; then
		verbose_flag="-v"
	fi

	# Check to see if we have to strip components based on the archive file has a parent directory
	if [ "${strip_components}" -eq 0 ]; then
		if tar -tf "${archive_file}" | head -1 | grep -q '/'; then
			msg "Archive has a parent directory, setting strip_components to 1"
			strip_components=1
		else
			msg "Archive does not have a parent directory, setting strip_components to 0"
			strip_components=0
		fi
	fi

	case ${archive_file} in
	*.tar.bz2 | *.tbz2)
		tar -xjf "${archive_file}" -C "${dest_dir}" --strip-components="${strip_components}" "${verbose_flag}"
		;;
	*.tar.xz | *.txz)
		tar -xJf "${archive_file}" -C "${dest_dir}" --strip-components="${strip_components}" "${verbose_flag}"
		;;
	*.tar.gz | *.tgz)
		tar -xzf "${archive_file}" -C "${dest_dir}" --strip-components="${strip_components}" "${verbose_flag}"
		;;
	*.zip)
		unzip -q "${archive_file}" -d "${dest_dir}"
		;;
	*)
		msg "Unknown archive format: ${archive_file}"
		exit 1
		;;
	esac
}

echo "Downloading toolchain tarball..."

mkdir -p "${TOOLCHAIN_DIR}"
wget -O "${TOOLCHAIN_DIR}/${TOOLCHAIN_TARBALL}" "${TOOLCHAIN_TARBALL_URL}"

echo "Extracting toolchain..."

extract_file "${TOOLCHAIN_DIR}/${TOOLCHAIN_TARBALL}" "${TOOLCHAIN_DIR}"

echo "Setting up target build directory..."

mkdir -p "${TARGET_BUILD_DIR}"

# Run toolchain relocate script if it exists
if [ -f "${TOOLCHAIN_DIR}/relocate-toolchain.sh" ]; then
    echo "Relocating toolchain..."
    bash "${TOOLCHAIN_DIR}/relocate-toolchain.sh" "${TARGET_BUILD_DIR}"
else
    echo "No relocate-toolchain.sh script found, please ensure the toolchain is correctly set up."
    exit 1
fi



