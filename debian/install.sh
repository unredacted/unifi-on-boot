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
# postinst handles systemctl enable + daemon-reload.
# We also need to start the main service explicitly because it gets enabled
# mid-boot after multi-user.target has already evaluated its dependencies.
# This is safe: install.sh only runs from a systemd service at boot time,
# not during interactive SSH sessions, so Tailscale restarts won't disrupt anything.
if dpkg -i "${DEB}"; then
    log "Package restored successfully"

    # Wait for actual network connectivity before starting the main service.
    # network-online.target may be reached before DNS/routing are fully ready,
    # especially after firmware upgrades. Scripts in on_boot.d need internet
    # access to download packages, add repo keys, etc.
    log "Waiting for network connectivity..."
    for i in $(seq 1 30); do
        if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 || \
           ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            log "Network is ready (attempt ${i})"
            break
        fi
        if [ "$i" -eq 30 ]; then
            log "WARNING: Network not ready after 60s, starting service anyway"
        fi
        sleep 2
    done

    # Start the main service so on_boot.d scripts run on this boot
    if systemctl start "${PACKAGE_NAME}.service" 2>/dev/null; then
        log "Service started — on_boot.d scripts executed"
    else
        log "WARNING: Could not start service (scripts will run on next boot)"
    fi
else
    log "ERROR: Failed to restore package"
    exit 1
fi
