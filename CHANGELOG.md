# CHANGELOG (0.9.X)

## 0.9.0 (:soon:)

### Backwards incompatible changes from 0.8.0

### Hotupgrade
 * Hotupgrade from 0.8.0 to 0.9.0 is not viable since the previous version doesn't support it.

### Installer Actions
 1. It’s not mandatory, but it’s recommended to update `deployex.sh` so it can support custom installation, hotupgrades and changing folder for log directories.
 ```bash
 rm deployex.sh
 wget https://github.com/thiagoesteves/deployex/releases/download/0.9.0/deployex.sh
 chmod a+x deployex.sh
 ./deployex.sh --install
 ```

### Bug fixes
 * None

### Enhancements
 * [`ISSUE-188`](https://github.com/thiagoesteves/deployex/issues/188) Add DeployEx Secrets via environment vars
 * [`PULL-189`](https://github.com/thiagoesteves/deployex/pull/189) Adding hot upgrade functionality for DeployEx itself via CLI
 * [`PULL-193`](https://github.com/thiagoesteves/deployex/pull/193) Adding UI/UX for hotupgrading deployex itself

# Host Binaries Available

This release includes binaries for the following Ubuntu versions:

 * Ubuntu 24.04 with OTP 27 - [deployex-ubuntu-24.04-otp-27.tar.gz](https://github.com/thiagoesteves/deployex/tree/main/devops/releases/otp-27/.tool-versions)
 * Ubuntu 24.04 with OTP 28 - [deployex-ubuntu-24.04-otp-28.tar.gz](https://github.com/thiagoesteves/deployex/tree/main/devops/releases/otp-28/.tool-versions)

 You can use these pre-built binaries, or you can build your own if preferred.

# Previous Releases
 * [0.8.0 🚀 (2025-11-20)](https://github.com/thiagoesteves/deployex/blob/0.8.0/CHANGELOG.md)
 * [0.7.3 🚀 (2025-10-28)](https://github.com/thiagoesteves/deployex/blob/0.7.3/CHANGELOG.md)
 * [0.7.2 🚀 (2025-10-16)](https://github.com/thiagoesteves/deployex/blob/0.7.2/CHANGELOG.md)
 * [0.7.1 🚀 (2025-10-15)](https://github.com/thiagoesteves/deployex/blob/0.7.1/CHANGELOG.md)
 * [0.7.0 🚀 (2025-10-07)](https://github.com/thiagoesteves/deployex/blob/0.7.0/CHANGELOG.md)
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