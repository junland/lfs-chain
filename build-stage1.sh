#!/bin/bash

set -euo pipefail

TOOLCHAIN_TARBALL_URL="https://toolchains.bootlin.com/downloads/releases/toolchains/aarch64/tarballs/aarch64--glibc--stable-2025.08-1.tar.xz"
TOOLCHAIN_DIR=${TOOLCHAIN_DIR:-"${PWD}/toolchain"}
TOOLCHAIN_TARBALL_FILENAME=${TOOLCHAIN_TARBALL_FILENAME:-"aarch64-glibc-stable-2025.08-1.tar.xz"}
TARGET_ROOTFS_DIR=${TARGET_ROOTFS_DIR:-"${PWD}/target-rootfs"}
TARGET_TRIPLET="${TARGET_TRIPLET:-aarch64-buildroot-linux-gnu}"

SOURCES_DIR=${SOURCES_DIR:-"${TARGET_ROOTFS_DIR}/sources"}
SOURCES_LIST=${SOURCES_LIST:-"${PWD}/data/sources.list"}
SOURCES_BUILD_DIR=${SOURCES_BUILD_DIR:-"${TARGET_ROOTFS_DIR}/build"}

# Export cross-compiler environment variables for configure scripts
export CC="${TARGET_TRIPLET}-gcc"
export CXX="${TARGET_TRIPLET}-g++"
export AR="${TARGET_TRIPLET}-ar"
export AS="${TARGET_TRIPLET}-as"
export LD="${TARGET_TRIPLET}-ld"
export RANLIB="${TARGET_TRIPLET}-ranlib"
export STRIP="${TARGET_TRIPLET}-strip"

msg() {
	echo " ===> $*"
}

extract_file() {
	local archive_file=$1
	local dest_dir=$2

	# Use environment variables with defaults
	local strip_components=${EXTRACT_FILE_STRIP_COMPONENTS:-1}
	local verbose=${EXTRACT_FILE_VERBOSE_EXTRACT:-false}

	# Make sure the archive file exists, if not find another archive file with a different extension.
	if [ ! -f "${archive_file}" ]; then
		msg "Archive file ${archive_file} does not exist, searching for alternative..."
		archive_file=$(find "${SOURCES_DIR}" -name "$(basename "${archive_file}" | sed 's/\.[^.]*$//').*" | head -1)
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

clean_build_dir() {
	msg "Cleaning build directory..."
	rm -rf "$SOURCES_BUILD_DIR"
}

msg "Build Information:"
echo "  Toolchain URL:       ${TOOLCHAIN_TARBALL_URL}"
echo "  Toolchain Directory: ${TOOLCHAIN_DIR}"
echo "  Target RootFS Dir:   ${TARGET_ROOTFS_DIR}"
echo "  Target Triplet:      ${TARGET_TRIPLET}"
echo "  Toolchain Tarball:   ${TOOLCHAIN_TARBALL_FILENAME}"
echo "  Sources List:        ${SOURCES_LIST}"
echo "  Sources Dir:         ${SOURCES_DIR}"
echo "  Sources Build Dir:   ${SOURCES_BUILD_DIR}"
echo "  GCC:                 ${CC}"
echo "  CXX:                 ${CXX}"
echo "  AR:                  ${AR}"
echo "  AS:                  ${AS}"
echo "  LD:                  ${LD}"
echo "  RANLIB:              ${RANLIB}"
echo "  STRIP:               ${STRIP}"

msg "Cleaning up any previous build artifacts..."

rm -rf "${TOOLCHAIN_DIR}" "${TARGET_ROOTFS_DIR}" "${SOURCES_BUILD_DIR}" "${SOURCES_DIR}"

msg "Downloading toolchain tarball..."

mkdir -vp "${TOOLCHAIN_DIR}"

wget -nv --tries=15 --waitretry=15 -O "${TOOLCHAIN_DIR}/${TOOLCHAIN_TARBALL_FILENAME}" "${TOOLCHAIN_TARBALL_URL}"

msg "Extracting toolchain..."

extract_file "${TOOLCHAIN_DIR}/${TOOLCHAIN_TARBALL_FILENAME}" "${TOOLCHAIN_DIR}"

# Run toolchain relocate script if it exists
if [ -f "${TOOLCHAIN_DIR}/relocate-sdk.sh" ]; then
    msg "Relocating toolchain..."
    bash "${TOOLCHAIN_DIR}/relocate-sdk.sh" "${TOOLCHAIN_DIR}"
else
    msg "No relocate-sdk.sh script found, please ensure the toolchain is correctly set up."
    exit 1
fi

export PATH="${TOOLCHAIN_DIR}/bin:${PATH}"

msg "Setting up target root filesystem directory..."

mkdir -p "${TARGET_ROOTFS_DIR}"

mkdir -vp "$TARGET_ROOTFS_DIR"/{etc,var} "$TARGET_ROOTFS_DIR"/usr/{bin,lib,sbin}

for i in bin lib sbin; do
	msg "Creating symlink $TARGET_ROOTFS_DIR/$i -> usr/$i"
	ln -sv usr/$i "$TARGET_ROOTFS_DIR"/$i
done

msg "Creating symlink $TARGET_ROOTFS_DIR/lib64 -> usr/lib"
ln -sv usr/lib "$TARGET_ROOTFS_DIR"/lib64

# Download all source files listed in sources.list file
msg "Downloading source files..."

wget -nv --tries=15 --waitretry=15 --input-file="${SOURCES_LIST}" --directory-prefix="${SOURCES_DIR}"

msg "Starting build for m4..."

extract_file "${SOURCES_DIR}/m4-1.4.20.tar.gz" "${SOURCES_BUILD_DIR}/m4-src"

cd "${SOURCES_BUILD_DIR}/m4-src"

./configure --prefix="/usr" --host=${TARGET_TRIPLET} --build=$(build-aux/config.guess) 

make -j$(nproc)

make DESTDIR="${TARGET_ROOTFS_DIR}" install

clean_build_dir

msg "Starting build for ncurses..."

extract_file "${SOURCES_DIR}/ncurses-6.5-20250809.tgz" "${SOURCES_BUILD_DIR}/ncurses-src"

cd "${SOURCES_BUILD_DIR}/ncurses-src"

mkdir build

pushd build
../configure AWK=gawk CC=gcc
CC=gcc make -C include
CC=gcc make -C progs tic
install progs/tic ${TOOLCHAIN_DIR}/bin
popd

./configure \
            --prefix=/usr                \
            --host=${TARGET_TRIPLET}     \
            --build=$(./config.guess)    \
            --mandir=/usr/share/man      \
            --with-manpage-format=normal \
            --with-shared                \
            --without-normal             \
            --with-cxx-shared            \
            --without-debug              \
            --without-ada                \
            --disable-stripping          \
            AWK=gawk

make -j$(nproc)

make DESTDIR="${TARGET_ROOTFS_DIR}" install

clean_build_dir

msg "Starting build for bash..."

extract_file "${SOURCES_DIR}/bash-5.3.tar.gz" "${SOURCES_BUILD_DIR}/bash-src"

cd "${SOURCES_BUILD_DIR}/bash-src"

./configure --prefix=/usr                      \
            --build=$(sh support/config.guess) \
            --host=${TARGET_TRIPLET}           \
            --without-bash-malloc

make -j$(nproc)

make DESTDIR="${TARGET_ROOTFS_DIR}" install

ln -sv bash "${TARGET_ROOTFS_DIR}/usr/bin/sh"

clean_build_dir