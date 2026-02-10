# unifi-on-boot

A firmware-upgrade-proof on-boot script runner for UniFi devices. Executes scripts from `/data/on_boot.d/` on every boot and **survives firmware upgrades** by integrating with Ubiquiti's native `ubnt-dpkg-cache`/`ubnt-dpkg-restore` mechanism.

## Why Not udm-boot?

The popular `udm-boot` / `udm-boot-2x` packages from [unifios-utilities](https://github.com/unifi-utilities/unifios-utilities) break on firmware upgrades because they:

1. Don't register with `ubnt-dpkg-cache` → package isn't cached for restore
2. Don't register with `ubnt-dpkg-support` → `ubnt-dpkg-restore` ignores it
3. Have an empty `postinst` that relies on debhelper magic → service never re-enables

`unifi-on-boot` fixes all three issues with explicit persistence integration.

## Compatibility

| Firmware | Status |
|----------|--------|
| UniFi OS 2.x | ✅ Supported |
| UniFi OS 3.x | ✅ Supported |
| UniFi OS 4.x | ✅ Supported |
| UniFi OS 5.x | ✅ Supported |
| UniFi OS 1.x | ❌ Not supported (uses container architecture) |

Tested on: Enterprise Fortress Gateway (EFG)

## Install

### From GitHub Release

```bash
# Download the latest release
curl -fsSLO https://github.com/unredacted/unifi-on-boot/releases/latest/download/unifi-on-boot_1.0.0_all.deb

# Install
dpkg -i unifi-on-boot_1.0.0_all.deb
```

The package automatically:
- Enables and starts the `unifi-on-boot` systemd service
- Registers itself with `ubnt-dpkg-cache` for package caching
- Registers itself with `ubnt-dpkg-support` for firmware upgrade restore
- Saves its systemd status for service re-enablement after restore
- Creates `/data/on_boot.d/` if it doesn't exist

### Uninstall

```bash
# Remove (keeps /data/on_boot.d/ and scripts)
dpkg -r unifi-on-boot

# Purge (removes all persistent data + registrations)
dpkg -P unifi-on-boot
```

> **Note:** If you have `udm-boot` or `udm-boot-2x` installed, this package will conflict with them. Remove them first: `dpkg -r udm-boot udm-boot-2x`

## Usage

Place your scripts in `/data/on_boot.d/` on the UniFi device:

```bash
# Create a script
cat > /data/on_boot.d/10-example.sh << 'EOF'
#!/bin/bash
echo "Hello from on-boot!"
EOF
chmod +x /data/on_boot.d/10-example.sh
```

### Script Execution Rules

Scripts in `/data/on_boot.d/` are processed in sorted order:

| Condition | Action |
|-----------|--------|
| File has `+x` (executable) flag | **Executed** directly |
| File ends in `.sh` but not executable | **Sourced** (run in current shell) |
| Everything else | **Ignored** |

### Naming Convention

Use numeric prefixes for ordering:

```
/data/on_boot.d/
├── 01-network-setup.sh
├── 10-install-packages.sh
├── 20-configure-services.sh
└── 50-custom-script.sh
```

### Logs

```bash
# View service status
systemctl status unifi-on-boot

# View journal logs
journalctl -u unifi-on-boot

# View persistent log
cat /var/log/unifi-on-boot.log
```

### Manual Trigger

```bash
# Re-run all on-boot scripts without rebooting
systemctl restart unifi-on-boot
```

## How Firmware Upgrade Persistence Works

```
Firmware Upgrade
  → Root filesystem rebuilt
  → ubnt-dpkg-restore runs
  → Reads /etc/default/ubnt-dpkg-support (has "unifi-on-boot")
  → Finds .deb in /persistent/dpkg/<distro>/packages/
  → dpkg -i reinstalls the package
  → postinst runs: systemctl enable + start
  → Service starts, runs /data/on_boot.d/* scripts
```

The package hooks into three Ubiquiti persistence mechanisms:

1. **`ubnt-dpkg-cache`** — Caches the `.deb` to `/persistent/dpkg/` during install
2. **`ubnt-dpkg-support`** — Lists the package for restoration after firmware upgrade
3. **systemd status** — Saves enable/disable state so `restore_pkg_status()` re-enables the service

## Ansible Role

This repo includes an Ansible role at `ansible/` for automated deployment.

### Usage

Add the role to your playbook's `requirements.yml`:

```yaml
- name: unifi-on-boot
  src: git+https://github.com/unredacted/unifi-on-boot.git
  version: main
```

Install: `ansible-galaxy install -r requirements.yml`

### Example Playbook

```yaml
- hosts: unifi_devices
  roles:
    - role: unifi-on-boot
      vars:
        unifi_on_boot_version: "1.0.0"
        unifi_on_boot_scripts:
          - name: "10-setup-pathvector.sh"
            src: "pathvector-setup.sh.j2"
            mode: "0755"
        unifi_on_boot_run_after_deploy: true
        unifi_on_boot_debug: true
```

### Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `unifi_on_boot_version` | `"1.0.0"` | Version to install from GitHub releases |
| `unifi_on_boot_remove_conflicts` | `true` | Remove `udm-boot`/`udm-boot-2x` if present |
| `unifi_on_boot_scripts` | `[]` | List of scripts to deploy (see example above) |
| `unifi_on_boot_run_after_deploy` | `false` | Run on-boot scripts immediately after deploy |
| `unifi_on_boot_debug` | `false` | Show debug output and deployment summary |

The role will:
1. Remove conflicting `udm-boot` packages (if enabled)
2. Download and install the `.deb` from GitHub releases
3. Deploy scripts from templates to `/data/on_boot.d/`
4. Optionally trigger the on-boot service

## Building from Source

```bash
# Requires: dpkg-deb (available on Debian/Ubuntu)
./build.sh

# Output: dist/unifi-on-boot_1.0.0_all.deb
```

The build uses `dpkg-deb` directly — no debhelper or other build system dependencies.

## Recovery

If something goes wrong after a firmware upgrade:

```bash
# Check if the package was restored
dpkg -l | grep unifi-on-boot

# If not, re-install manually
dpkg -i /persistent/dpkg/*/packages/unifi-on-boot_*.deb

# Or download fresh
curl -fsSLO https://github.com/unredacted/unifi-on-boot/releases/latest/download/unifi-on-boot_1.0.0_all.deb
dpkg -i unifi-on-boot_1.0.0_all.deb
```

## Comparison with udm-boot

| Feature | unifi-on-boot | udm-boot-2x |
|---------|--------------|-------------|
| Survives firmware upgrades | ✅ Yes | ❌ No |
| `ubnt-dpkg-cache` integration | ✅ Yes | ❌ No |
| `ubnt-dpkg-support` integration | ✅ Yes | ❌ No |
| Explicit `systemctl enable` in postinst | ✅ Yes | ❌ Relies on debhelper |
| systemd status persistence | ✅ Yes | ❌ No |
| Clean uninstall (purge) | ✅ Yes | ⚠️ Partial |
| UniFi OS 4.x/5.x support | ✅ Yes | ⚠️ Broken |
| GitHub Actions CI | ✅ Yes | ❌ No |

## License

GPL-3.0 — see [LICENSE](LICENSE)
