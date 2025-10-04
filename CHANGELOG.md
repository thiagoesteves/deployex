# CHANGELOG (0.6.x)

## :soon: 0.7.0 ()

### Backwards incompatible changes for 0.6.1

#### Configuration Update Required: Replica Port Definition

The `initial_port` field has been replaced with a simpler `replica_ports` configuration to support dynamic port assignment for replicas.

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
 * None

### Bug fixes
 * None

### Enhancements
 * [`PULL-153`](https://github.com/thiagoesteves/deployex/pull/153) Prettify README and fixing typos
 * [`PULL-159`](https://github.com/thiagoesteves/deployex/pull/159) Amaru Integration
 * [`PULL-160`](https://github.com/thiagoesteves/deployex/pull/160) Adding multiple dynamic ports for application deployment based on the number of replicas
 * [`PULL-160`](https://github.com/thiagoesteves/deployex/pull/160) Adding health check path

## 0.6.1 🚀 (2025-08-29)

### Backwards incompatible changes for 0.6.0
 * None

### Installer Actions
 * None

### Bug fixes
 * None

### Enhancements
 * Update Observer Web version to 0.1.11

## 0.6.0 🚀 (2025-08-22)

### Backwards incompatible changes for 0.5.2
 * Projects using `OTP-26` version won't be supported since it doesn't support new `erlexec` versions (~2.2). If `OTP-26` is required, it is recommended to fork the repo and downgrade the `erlexec` to (2.0.7)

### Installer Actions
 * None

### Bug fixes
 * None

### Enhancements
 * [`ISSUE-151`](https://github.com/thiagoesteves/deployex/issues/151) Update DeployEx to use new `erlexec` versions and decommission releases for `OTP-26`

# Host Binaries Available

This release includes binaries for the following Ubuntu versions:

 * Ubuntu 24.04 with OTP 27 - [deployex-ubuntu-24.04-otp-27.tar.gz](https://github.com/thiagoesteves/deployex/tree/main/devops/releases/otp-27/.tool-versions)
 * Ubuntu 24.04 with OTP 28 - [deployex-ubuntu-24.04-otp-28.tar.gz](https://github.com/thiagoesteves/deployex/tree/main/devops/releases/otp-28/.tool-versions)

 You can use these pre-built binaries, or you can build your own if preferred.

# Previous Releases
 * [0.5.2 🚀 (2025-06-13)](https://github.com/thiagoesteves/deployex/blob/0.5.2/CHANGELOG.md)
 * [0.5.1 🚀 (2025-06-03)](https://github.com/thiagoesteves/deployex/blob/0.5.1/CHANGELOG.md)
 * [0.5.0 🚀 (2025-05-27)](https://github.com/thiagoesteves/deployex/blob/0.5.0/CHANGELOG.md)
 * [0.4.2 🚀 (2025-05-13)](https://github.com/thiagoesteves/deployex/blob/0.4.2/CHANGELOG.md)
 * [0.4.1 🚀 (2025-04-25)](https://github.com/thiagoesteves/deployex/blob/0.4.1/CHANGELOG.md)
 * [0.4.0 🚀 (2025-04-23)](https://github.com/thiagoesteves/deployex/blob/0.4.0/CHANGELOG.md)
 * [0.3.4 🚀 (2025-04-14)](https://github.com/thiagoesteves/deployex/blob/0.3.4/CHANGELOG.md)
 * [0.2.0 🚀 (2024-05-23)](https://github.com/thiagoesteves/deployex/blob/0.2.0/CHANGELOG.md)
 * [0.1.0 🚀 (2024-05-06)](https://github.com/thiagoesteves/deployex/blob/0.1.0/changelog.md)