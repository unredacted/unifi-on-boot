#!/bin/bash
# Build script for unifi-on-boot .deb package
# Produces unifi-on-boot_<version>_all.deb
# No debhelper dependency — uses dpkg-deb directly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEBIAN_DIR="${SCRIPT_DIR}/debian"
OUTPUT_DIR="${SCRIPT_DIR}/dist"

# Extract version from control file
VERSION=$(grep '^Version:' "${DEBIAN_DIR}/control" | awk '{print $2}')
PACKAGE_NAME="unifi-on-boot"
DEB_NAME="${PACKAGE_NAME}_${VERSION}_all.deb"

echo "Building ${DEB_NAME}..."

# Create build directory
BUILD_DIR=$(mktemp -d)
PKG_DIR="${BUILD_DIR}/${PACKAGE_NAME}_${VERSION}_all"
trap "rm -rf '${BUILD_DIR}'" EXIT

# Create package structure
mkdir -p "${PKG_DIR}/DEBIAN"
mkdir -p "${PKG_DIR}/lib/systemd/system"
mkdir -p "${PKG_DIR}/usr/sbin"

# Copy DEBIAN control files
cp "${DEBIAN_DIR}/control" "${PKG_DIR}/DEBIAN/control"

# Copy and set permissions on maintainer scripts
for script in postinst prerm postrm; do
    if [ -f "${DEBIAN_DIR}/${script}" ]; then
        cp "${DEBIAN_DIR}/${script}" "${PKG_DIR}/DEBIAN/${script}"
        chmod 0755 "${PKG_DIR}/DEBIAN/${script}"
    fi
done

# Install systemd service
cp "${DEBIAN_DIR}/unifi-on-boot.service" "${PKG_DIR}/lib/systemd/system/unifi-on-boot.service"
chmod 0644 "${PKG_DIR}/lib/systemd/system/unifi-on-boot.service"

# Install runner script
cp "${DEBIAN_DIR}/unifi-on-boot" "${PKG_DIR}/usr/sbin/unifi-on-boot"
chmod 0755 "${PKG_DIR}/usr/sbin/unifi-on-boot"

# Calculate installed size (in KB)
INSTALLED_SIZE=$(du -sk "${PKG_DIR}" | cut -f1)
echo "Installed-Size: ${INSTALLED_SIZE}" >> "${PKG_DIR}/DEBIAN/control"

# Build the .deb
mkdir -p "${OUTPUT_DIR}"
dpkg-deb --root-owner-group --build "${PKG_DIR}" "${OUTPUT_DIR}/${DEB_NAME}"

echo ""
echo "Build complete: ${OUTPUT_DIR}/${DEB_NAME}"
echo ""

# Show package info
dpkg-deb -I "${OUTPUT_DIR}/${DEB_NAME}"
echo ""
echo "Package contents:"
dpkg-deb -c "${OUTPUT_DIR}/${DEB_NAME}"
