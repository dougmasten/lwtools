#!/bin/sh
#
# Build script for the m6809 GCC cross-compiler with newlib.
#
# This script will optionally download, then patch and build GCC and
# newlib for the m6809 target, using lwtools as the assembler/linker.
#
# Usage:
#   ./build-gcc6809.sh [--fetch] [--prefix=/usr/local/m6809] [--clean] [--reconfigure]
#
# Prerequisites:
#   - lwtools (lwasm, lwlink, lwar) built and in PATH or in ../lwasm etc.
#   - GNU make, gawk, bison, flex, makeinfo (texinfo)
#   - GMP, MPFR, MPC (fetched automatically via GCC's download_prerequisites)
#   - A working C compiler for the host
#
# This script is resumable: re-run it after installing missing prerequisites
# and it will pick up where the previous run left off. Use --clean to start
# over, or --reconfigure to just re-run GCC's configure step.

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
CLEAN=no
RECONFIGURE=no

# --- Parse arguments ---
for arg in "$@"; do
	case "$arg" in
		--fetch)
			FETCH=yes
			;;
		--prefix=*)
			PREFIX="${arg#--prefix=}"
			;;
		--clean)
			CLEAN=yes
			;;
		--reconfigure)
			RECONFIGURE=yes
			;;
		--help|-h)
			echo "Usage: $0 [--fetch] [--prefix=DIR] [--clean] [--reconfigure]"
			echo ""
			echo "  --fetch        Download GCC and newlib source tarballs"
			echo "  --prefix       Installation prefix (default: /usr/local/m6809)"
			echo "  --clean        Remove build and unpacked source dirs before building"
			echo "  --reconfigure  Force re-running of GCC configure step"
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

# --- Optional clean ---
if [ "${CLEAN}" = "yes" ]; then
	echo "Cleaning previous build and unpacked sources..."
	rm -rf "${BUILDDIR}"
	rm -rf "${SCRIPTDIR}/${GCC_SRCDIR}"
	rm -rf "${SCRIPTDIR}/${NEWLIB_SRCDIR}"
fi

# --- Check prerequisites up front ---
missing=""
for tool in make gawk bison flex makeinfo patch tar curl; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		missing="${missing} ${tool}"
	fi
done
if [ -n "${missing}" ]; then
	echo "Error: missing required tools:${missing}" >&2
	echo "On macOS: brew install gawk bison flex texinfo" >&2
	echo "On Debian/Ubuntu: apt install build-essential gawk bison flex texinfo" >&2
	exit 1
fi
export AWK=gawk

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
# Dry-run patch first so a failure leaves the tree untouched and re-runnable.
if [ ! -d "${GCC_SRCDIR}" ]; then
	echo "Unpacking ${GCC_TARBALL}..."
	tar xjf "${GCC_TARBALL}"
fi

if [ ! -f "${GCC_SRCDIR}/.patched-${GCC_PATCH_LEVEL}" ]; then
	echo "Applying ${GCC_PATCH}..."
	cd "${GCC_SRCDIR}"
	if ! patch -p1 --dry-run --silent < "../${GCC_PATCH}"; then
		echo "Error: ${GCC_PATCH} would not apply cleanly." >&2
		echo "Re-run with --clean to start from a fresh tree." >&2
		exit 1
	fi
	patch -p1 < "../${GCC_PATCH}"
	touch ".patched-${GCC_PATCH_LEVEL}"
	cd "${SCRIPTDIR}"
fi

# --- Host-specific patches (applied to the unpacked GCC tree) ---
# GCC 4.6.4 predates Apple Silicon and has no aarch64-darwin host_hooks,
# which causes cc1 to fail linking with "Undefined symbols: _host_hooks".
# Add a trivial host-hook file and wire it into config.host.
if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ] && \
   [ ! -f "${GCC_SRCDIR}/.aarch64-darwin-host-hooks" ]; then
	echo "Adding aarch64-darwin host_hooks to GCC source tree..."
	mkdir -p "${GCC_SRCDIR}/gcc/config/aarch64"
	cat > "${GCC_SRCDIR}/gcc/config/aarch64/host-aarch64-darwin.c" <<'EOF'
/* aarch64-darwin host-specific hook definitions. */
#include "config.h"
#include "system.h"
#include "coretypes.h"
#include "hosthooks.h"
#include "hosthooks-def.h"
#include "config/host-darwin.h"

const struct host_hooks host_hooks = HOST_HOOKS_INITIALIZER;
EOF
	cat > "${GCC_SRCDIR}/gcc/config/aarch64/x-darwin" <<'EOF'
host-aarch64-darwin.o : $(srcdir)/config/aarch64/host-aarch64-darwin.c \
  $(CONFIG_H) $(SYSTEM_H) coretypes.h hosthooks.h $(HOSTHOOKS_DEF_H) \
  config/host-darwin.h
	$(COMPILER) -c $(ALL_COMPILERFLAGS) $(ALL_CPPFLAGS) $(INCLUDES) $<
EOF
	# Insert aarch64-darwin case into config.host, right after the i386/x86_64 darwin block.
	if ! grep -q "aarch64-\*-darwin" "${GCC_SRCDIR}/gcc/config.host"; then
		awk '
		/i\[34567\]86-\*-darwin\* \| x86_64-\*-darwin\*\)/ { in_block = 1 }
		{ print }
		in_block && /^    ;;/ {
			print "  aarch64-*-darwin* | arm64-*-darwin* | arm-*-darwin*)"
			print "    out_host_hook_obj=\"${out_host_hook_obj} host-aarch64-darwin.o\""
			print "    host_xmake_file=\"${host_xmake_file} aarch64/x-darwin\""
			print "    ;;"
			in_block = 0
		}
		' "${GCC_SRCDIR}/gcc/config.host" > "${GCC_SRCDIR}/gcc/config.host.new"
		mv "${GCC_SRCDIR}/gcc/config.host.new" "${GCC_SRCDIR}/gcc/config.host"
	fi
	touch "${GCC_SRCDIR}/.aarch64-darwin-host-hooks"
	# Force reconfigure so the new config.host entry takes effect.
	RECONFIGURE=yes
fi

# --- Locate GCC prerequisites (GMP, MPFR, MPC) ---
# Prefer system/Homebrew-installed copies; fall back to GCC's download_prerequisites.
GMP_PREFIX=""
MPFR_PREFIX=""
MPC_PREFIX=""
if command -v brew >/dev/null 2>&1; then
	GMP_PREFIX=$(brew --prefix gmp 2>/dev/null || true)
	MPFR_PREFIX=$(brew --prefix mpfr 2>/dev/null || true)
	MPC_PREFIX=$(brew --prefix libmpc 2>/dev/null || true)
fi

if [ -n "${GMP_PREFIX}" ] && [ -n "${MPFR_PREFIX}" ] && [ -n "${MPC_PREFIX}" ] && \
   [ -d "${GMP_PREFIX}" ] && [ -d "${MPFR_PREFIX}" ] && [ -d "${MPC_PREFIX}" ]; then
	echo "Using Homebrew GMP/MPFR/MPC:"
	echo "  GMP:  ${GMP_PREFIX}"
	echo "  MPFR: ${MPFR_PREFIX}"
	echo "  MPC:  ${MPC_PREFIX}"
elif [ ! -d "${GCC_SRCDIR}/gmp" ] || [ ! -d "${GCC_SRCDIR}/mpfr" ] || [ ! -d "${GCC_SRCDIR}/mpc" ]; then
	echo "GMP/MPFR/MPC not found via Homebrew; fetching into GCC source tree..."
	if ! command -v wget >/dev/null 2>&1; then
		echo "Error: contrib/download_prerequisites requires wget, which is not installed." >&2
		echo "Either:" >&2
		echo "  brew install gmp mpfr libmpc   (preferred on macOS)" >&2
		echo "  brew install wget              (to use GCC's bundled download)" >&2
		exit 1
	fi
	cd "${GCC_SRCDIR}"
	./contrib/download_prerequisites
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
	if ! patch -p1 --dry-run --silent < "../${NEWLIB_PATCH}"; then
		echo "Error: ${NEWLIB_PATCH} would not apply cleanly." >&2
		echo "Re-run with --clean to start from a fresh tree." >&2
		exit 1
	fi
	patch -p1 < "../${NEWLIB_PATCH}"
	touch ".patched-${NEWLIB_PATCH_LEVEL}"
	cd "${SCRIPTDIR}"
fi

# --- Symlink newlib into GCC tree ---
cd "${GCC_SRCDIR}"
[ -L newlib ] || ln -sf "../${NEWLIB_SRCDIR}/newlib" newlib
[ -L libgloss ] || ln -sf "../${NEWLIB_SRCDIR}/libgloss" libgloss
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

if [ "${RECONFIGURE}" = "yes" ]; then
	echo "Forcing re-configure: removing existing build files..."
	rm -f Makefile config.status
fi

if [ ! -f Makefile ]; then
	echo "Configuring GCC..."
	CONFIGURE_EXTRA=""
	if [ -n "${GMP_PREFIX}" ] && [ -d "${GMP_PREFIX}" ]; then
		CONFIGURE_EXTRA="${CONFIGURE_EXTRA} --with-gmp=${GMP_PREFIX}"
	fi
	if [ -n "${MPFR_PREFIX}" ] && [ -d "${MPFR_PREFIX}" ]; then
		CONFIGURE_EXTRA="${CONFIGURE_EXTRA} --with-mpfr=${MPFR_PREFIX}"
	fi
	if [ -n "${MPC_PREFIX}" ] && [ -d "${MPC_PREFIX}" ]; then
		CONFIGURE_EXTRA="${CONFIGURE_EXTRA} --with-mpc=${MPC_PREFIX}"
	fi
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
		--with-ar="${PREFIX}/bin/m6809-unknown-ar" \
		${CONFIGURE_EXTRA}
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
