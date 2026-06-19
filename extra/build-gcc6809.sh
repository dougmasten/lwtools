#!/bin/sh
#
# Build script for the m6809 GCC cross-compiler with newlib.
#
# This script will optionally download, then patch and build GCC and
# newlib for the m6809 target, using lwtools as the assembler/linker.
#
# Usage:
#   ./build-gcc6809.sh [--fetch] [--prefix=/usr/local/m6809]
#
# Prerequisites:
#   - lwtools (lwasm, lwlink, lwar) built and in PATH or in ../lwasm etc.
#   - GNU make, gawk, bison, flex
#   - A working C compiler for the host

set -e

# --- Configurable versions and patch levels ---
GCC_VERSION=4.6.4
GCC_PATCH_LEVEL=11
NEWLIB_VERSION=4.6.0.20260123
NEWLIB_PATCH_LEVEL=1

# --- Derived names ---
GCC_TARBALL=gcc-${GCC_VERSION}.tar.bz2
GCC_URL=https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/${GCC_TARBALL}
GCC_SRCDIR=gcc-${GCC_VERSION}
GCC_PATCH=gcc6809lw-${GCC_VERSION}-${GCC_PATCH_LEVEL}.patch

NEWLIB_TARBALL=newlib-${NEWLIB_VERSION}.tar.gz
NEWLIB_URL=https://sourceware.org/pub/newlib/${NEWLIB_TARBALL}
NEWLIB_SRCDIR=newlib-${NEWLIB_VERSION}
NEWLIB_PATCH=newlib6809lw-$(echo ${NEWLIB_VERSION} | sed 's/\..*//')-${NEWLIB_PATCH_LEVEL}.patch

PREFIX=/usr/local/m6809
FETCH=no

# --- Parse arguments ---
for arg in "$@"; do
	case "$arg" in
		--fetch)
			FETCH=yes
			;;
		--prefix=*)
			PREFIX="${arg#--prefix=}"
			;;
		--help|-h)
			echo "Usage: $0 [--fetch] [--prefix=DIR]"
			echo ""
			echo "  --fetch    Download GCC and newlib source tarballs"
			echo "  --prefix   Installation prefix (default: /usr/local/m6809)"
			exit 0
			;;
		*)
			echo "Unknown option: $arg" >&2
			exit 1
			;;
	esac
done

SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)
BUILDDIR=${SCRIPTDIR}/gcc-build

# --- Locate lwtools ---
LWTOOLSDIR=$(cd "${SCRIPTDIR}/.." && pwd)
LWASM=${LWTOOLSDIR}/lwasm/lwasm
LWLINK=${LWTOOLSDIR}/lwlink/lwlink
LWAR=${LWTOOLSDIR}/lwar/lwar

if [ ! -x "${LWASM}" ]; then
	# Try PATH
	if command -v lwasm >/dev/null 2>&1; then
		LWASM=$(command -v lwasm)
		LWLINK=$(command -v lwlink)
		LWAR=$(command -v lwar)
	else
		echo "Error: lwtools not found. Build lwtools first or add to PATH." >&2
		exit 1
	fi
fi

LWTOOLS_BINDIR=$(dirname "${LWASM}")
echo "Using lwtools from: ${LWTOOLS_BINDIR}"

# --- Check for gawk ---
if ! command -v gawk >/dev/null 2>&1; then
	echo "Error: gawk is required (macOS awk causes build failures)." >&2
	echo "Install with: brew install gawk" >&2
	exit 1
fi
export AWK=gawk

# --- Fetch sources ---
cd "${SCRIPTDIR}"

if [ "${FETCH}" = "yes" ]; then
	if [ ! -f "${GCC_TARBALL}" ]; then
		echo "Downloading ${GCC_TARBALL}..."
		curl -L -o "${GCC_TARBALL}" "${GCC_URL}"
	fi
	if [ ! -f "${NEWLIB_TARBALL}" ]; then
		echo "Downloading ${NEWLIB_TARBALL}..."
		curl -L -o "${NEWLIB_TARBALL}" "${NEWLIB_URL}"
	fi
fi

# --- Verify sources exist ---
for f in "${GCC_TARBALL}" "${GCC_PATCH}" "${NEWLIB_TARBALL}" "${NEWLIB_PATCH}"; do
	if [ ! -f "$f" ]; then
		echo "Error: $f not found. Use --fetch to download, or place files in ${SCRIPTDIR}." >&2
		exit 1
	fi
done

# --- Unpack and patch GCC ---
if [ ! -d "${GCC_SRCDIR}" ]; then
	echo "Unpacking ${GCC_TARBALL}..."
	tar xjf "${GCC_TARBALL}"
fi

if [ ! -f "${GCC_SRCDIR}/.patched-${GCC_PATCH_LEVEL}" ]; then
	echo "Applying ${GCC_PATCH}..."
	cd "${GCC_SRCDIR}"
	patch -p1 < "../${GCC_PATCH}"
	touch ".patched-${GCC_PATCH_LEVEL}"
	cd "${SCRIPTDIR}"
fi

# --- Unpack and patch newlib ---
if [ ! -d "${NEWLIB_SRCDIR}" ]; then
	echo "Unpacking ${NEWLIB_TARBALL}..."
	tar xzf "${NEWLIB_TARBALL}"
fi

if [ ! -f "${NEWLIB_SRCDIR}/.patched-${NEWLIB_PATCH_LEVEL}" ]; then
	echo "Applying ${NEWLIB_PATCH}..."
	cd "${NEWLIB_SRCDIR}"
	patch -p1 < "../${NEWLIB_PATCH}"
	touch ".patched-${NEWLIB_PATCH_LEVEL}"
	cd "${SCRIPTDIR}"
fi

# --- Symlink newlib into GCC tree ---
cd "${GCC_SRCDIR}"
[ -L newlib ] || ln -s "../${NEWLIB_SRCDIR}/newlib" newlib
[ -L libgloss ] || ln -s "../${NEWLIB_SRCDIR}/libgloss" libgloss
cd "${SCRIPTDIR}"

# --- Install toolchain wrapper scripts ---
echo "Installing toolchain scripts to ${PREFIX}/bin..."
mkdir -p "${PREFIX}/bin"
cp "${SCRIPTDIR}/as" "${PREFIX}/bin/m6809-unknown-as"
cp "${SCRIPTDIR}/ld" "${PREFIX}/bin/m6809-unknown-ld"
cp "${SCRIPTDIR}/ar" "${PREFIX}/bin/m6809-unknown-ar"
chmod +x "${PREFIX}/bin"/m6809-unknown-{as,ld,ar}

for tool in nm objdump ranlib strip; do
	ln -sf /usr/bin/true "${PREFIX}/bin/m6809-unknown-${tool}"
done

# --- Configure ---
export PATH="${PREFIX}/bin:${LWTOOLS_BINDIR}:${PATH}"

mkdir -p "${BUILDDIR}"
cd "${BUILDDIR}"

if [ ! -f Makefile ]; then
	echo "Configuring GCC..."
	"../${GCC_SRCDIR}/configure" \
		--enable-languages=c \
		--target=m6809-unknown \
		--program-prefix=m6809-unknown- \
		--enable-obsolete \
		--srcdir="../${GCC_SRCDIR}" \
		--disable-threads \
		--disable-nls \
		--disable-libssp \
		--with-newlib \
		--prefix="${PREFIX}" \
		--with-as="${PREFIX}/bin/m6809-unknown-as" \
		--with-ld="${PREFIX}/bin/m6809-unknown-ld" \
		--with-ar="${PREFIX}/bin/m6809-unknown-ar"
fi

# --- Build ---
echo "Building GCC..."
make all-gcc

echo "Building libgcc..."
make all-target-libgcc

echo "Building newlib..."
make all-target-newlib

# --- Install ---
echo "Installing GCC and libgcc to ${PREFIX}..."
make install-gcc install-target-libgcc

echo "Installing newlib libraries and headers to ${PREFIX}..."
mkdir -p "${PREFIX}/m6809-unknown/lib" "${PREFIX}/m6809-unknown/include"

NEWLIB_BUILDDIR="${BUILDDIR}/m6809-unknown/newlib"
for lib in libc.a libm.a libg.a; do
	if [ -f "${NEWLIB_BUILDDIR}/${lib}" ]; then
		cp "${NEWLIB_BUILDDIR}/${lib}" "${PREFIX}/m6809-unknown/lib/"
	fi
done

cp -r "${NEWLIB_BUILDDIR}/targ-include"/* "${PREFIX}/m6809-unknown/include/"
cp -r "${SCRIPTDIR}/${GCC_SRCDIR}/newlib/libc/include"/* "${PREFIX}/m6809-unknown/include/"

echo ""
echo "Build complete. Installed to ${PREFIX}"
echo "Ensure lwtools and ${PREFIX}/bin are in your PATH to use the toolchain."
