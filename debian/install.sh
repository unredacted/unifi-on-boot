#!/bin/bash
# Self-restore unifi-on-boot after firmware upgrade
# This script is stored in /data/unifi-on-boot/ (persistent) and runs
# via a systemd service symlinked from the overlay upper dir.

set -e

PACKAGE_NAME="unifi-on-boot"
LOG_TAG="[${PACKAGE_NAME}-install]"

log() {
    echo "${LOG_TAG} $*"
    logger -t "${PACKAGE_NAME}-install" "$*" 2>/dev/null || true
}

# Check if already installed
if dpkg -l "${PACKAGE_NAME}" 2>/dev/null | grep -q '^ii'; then
    log "Already installed, nothing to do"
    exit 0
fi

log "Package not installed, attempting restore..."

# Find the cached .deb in persistent storage
DEB=""

# First check /persistent/dpkg/ (where ubnt-dpkg-cache stores it)
DEB=$(find /persistent/dpkg/*/packages/ -name "${PACKAGE_NAME}_*.deb" -type f 2>/dev/null | sort -V | tail -1)

# Fallback to /data/unifi-on-boot/
if [ -z "${DEB}" ] && [ -f "/data/unifi-on-boot/${PACKAGE_NAME}.deb" ]; then
    DEB="/data/unifi-on-boot/${PACKAGE_NAME}.deb"
fi

if [ -z "${DEB}" ] || [ ! -f "${DEB}" ]; then
    log "ERROR: No cached .deb found, cannot restore"
    exit 1
fi

log "Restoring from: ${DEB}"

# Install the package
# Note: postinst handles systemctl enable + daemon-reload.
# Do NOT start the service here — it would run all on_boot.d scripts
# (including Tailscale) which can disrupt network connectivity.
# The main service starts later in the same boot via WantedBy=multi-user.target.
if dpkg -i "${DEB}"; then
    log "Package restored successfully (service will start later in boot)"
else
    log "ERROR: Failed to restore package"
    exit 1
fi
