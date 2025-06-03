# CHANGELOG (0.5.x)

## 0.5.1 🚀 (2025-06-03)

### Backwards incompatible changes for 0.5.0
 * This version requires to modify the monitored applications release file `rel/env.sh.eex` to not export `RELEASE_NODE`

### Installer Actions
 * None

### Bug fixes
 * None

### Enhancements
 * [`ISSUE-138`](https://github.com/thiagoesteves/deployex/issues/138) Deprecate RELEASE_NODE_SUFFIX in favor of RELEASE_NODE=sname
 * [`ISSUE-109`](https://github.com/thiagoesteves/deployex/issues/109) Add support for different application
 * [`PULL-142`](https://github.com/thiagoesteves/deployex/pull/142) Modify code to capture logs for migrations

## 0.5.0 🚀 (2025-05-27)

### Backwards incompatible changes for 0.4.2
 * This version has a major change from instance to node/sname, this will require to prune existing version data.

### Installer Actions
 * Run `./depoloyex.sh --install deployex.yaml` to prune existing version data

### Bug fixes
 * None

### Enhancements
 * [`ISSUE-64`](https://github.com/thiagoesteves/deployex/issues/64) Modify Deployex to use node/sname instead instance

# Host Binaries Available

This release includes binaries for the following Ubuntu versions:

 * Ubuntu 24.04 with OTP 26 - [deployex-ubuntu-24.04-otp-26.tar.gz](https://github.com/thiagoesteves/deployex/tree/main/devops/releases/otp-26/.tool-versions)
 * Ubuntu 24.04 with OTP 27 - [deployex-ubuntu-24.04-otp-27.tar.gz](https://github.com/thiagoesteves/deployex/tree/main/devops/releases/otp-27/.tool-versions)

 You can use these pre-built binaries, or you can build your own if preferred.

# Previous Releases
 * [0.4.2 🚀 (2025-05-13)](https://github.com/thiagoesteves/deployex/blob/0.4.2/CHANGELOG.md)
 * [0.4.1 🚀 (2025-04-25)](https://github.com/thiagoesteves/deployex/blob/0.4.1/CHANGELOG.md)
 * [0.4.0 🚀 (2025-04-23)](https://github.com/thiagoesteves/deployex/blob/0.4.0/CHANGELOG.md)
 * [0.3.4 🚀 (2025-04-14)](https://github.com/thiagoesteves/deployex/blob/0.3.4/CHANGELOG.md)
 * [0.2.0 🚀 (2024-05-23)](https://github.com/thiagoesteves/deployex/blob/0.2.0/CHANGELOG.md)
 * [0.1.0 🚀 (2024-05-06)](https://github.com/thiagoesteves/deployex/blob/0.1.0/changelog.md)