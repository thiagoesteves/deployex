# CHANGELOG (0.7.X)

## 0.7.1 🚀 (2025-10-15)

### Backwards incompatible changes for 0.7.0
 * None

### Installer Actions
 * (Only if you run DeployEx for multiple applications) Update `deployex.sh` script via:
   `wget https://github.com/thiagoesteves/deployex/releases/download/0.7.1/deployex.sh`

### Bug fixes
 * [`PULL-164`](https://github.com/thiagoesteves/deployex/pull/164) Updating installer to give log permissions to multiple apps

### Enhancements
 * [`PULL-165`](https://github.com/thiagoesteves/deployex/pull/165) Adding plug to avoid health check logging

## 0.7.0 🚀 (2025-10-07)

### Backwards incompatible changes for 0.6.1

#### Configuration Update Required: Replica Port Definition

The `initial_port` field has been replaced with a `replica_ports` configuration to support dynamic port assignment for replicas.

**Before (0.6.0 and earlier):**
```yaml
applications:
    initial_port: 4000
```
**After (0.7.0):**
```yaml
applications:
    replica_ports:
      - key: PORT
        base: 4000
```

### Installer Actions
 * (Only for debian hosts) Update `deployex.sh` script via:
   `wget https://github.com/thiagoesteves/deployex/releases/download/0.7.0/deployex.sh`

### Bug fixes
 * None

### Enhancements
 * [`PULL-153`](https://github.com/thiagoesteves/deployex/pull/153) Prettify README and fixing typos
 * [`PULL-159`](https://github.com/thiagoesteves/deployex/pull/159) Amaru Integration
 * [`PULL-160`](https://github.com/thiagoesteves/deployex/pull/160) Adding multiple dynamic ports for application deployment based on the number of replicas
 * [`PULL-160`](https://github.com/thiagoesteves/deployex/pull/160) Adding health check path
 * [`PULL-161`](https://github.com/thiagoesteves/deployex/pull/161) Adding new Feature to verify latest versions on Github for DeployEx
 * [`PULL-161`](https://github.com/thiagoesteves/deployex/pull/162) Adding Checksum for released files

# Host Binaries Available

This release includes binaries for the following Ubuntu versions:

 * Ubuntu 24.04 with OTP 27 - [deployex-ubuntu-24.04-otp-27.tar.gz](https://github.com/thiagoesteves/deployex/tree/main/devops/releases/otp-27/.tool-versions)
 * Ubuntu 24.04 with OTP 28 - [deployex-ubuntu-24.04-otp-28.tar.gz](https://github.com/thiagoesteves/deployex/tree/main/devops/releases/otp-28/.tool-versions)

 You can use these pre-built binaries, or you can build your own if preferred.

# Previous Releases
 * [0.6.1 🚀 (2025-08-29)](https://github.com/thiagoesteves/deployex/blob/0.6.1/CHANGELOG.md)
 * [0.6.0 🚀 (2025-08-22)](https://github.com/thiagoesteves/deployex/blob/0.6.0/CHANGELOG.md)
 * [0.5.2 🚀 (2025-06-13)](https://github.com/thiagoesteves/deployex/blob/0.5.2/CHANGELOG.md)
 * [0.5.1 🚀 (2025-06-03)](https://github.com/thiagoesteves/deployex/blob/0.5.1/CHANGELOG.md)
 * [0.5.0 🚀 (2025-05-27)](https://github.com/thiagoesteves/deployex/blob/0.5.0/CHANGELOG.md)
 * [0.4.2 🚀 (2025-05-13)](https://github.com/thiagoesteves/deployex/blob/0.4.2/CHANGELOG.md)
 * [0.4.1 🚀 (2025-04-25)](https://github.com/thiagoesteves/deployex/blob/0.4.1/CHANGELOG.md)
 * [0.4.0 🚀 (2025-04-23)](https://github.com/thiagoesteves/deployex/blob/0.4.0/CHANGELOG.md)
 * [0.3.4 🚀 (2025-04-14)](https://github.com/thiagoesteves/deployex/blob/0.3.4/CHANGELOG.md)
 * [0.2.0 🚀 (2024-05-23)](https://github.com/thiagoesteves/deployex/blob/0.2.0/CHANGELOG.md)
 * [0.1.0 🚀 (2024-05-06)](https://github.com/thiagoesteves/deployex/blob/0.1.0/changelog.md)