# CHANGELOG (0.4.x)

## 0.4.1 🚀 (2025-04-25)

### Backwards incompatible changes for 0.4.0
 * None

### Installer Actions
 * None

### Bug fixes
 * None

### Enhancements
 * [[`PR-113`](https://github.com/thiagoesteves/deployex/pull/113)] Moving project to Elixir Umbrella scaffolding

## 0.4.0 🚀 (2025-04-23)

### Backwards incompatible changes for 0.3.4
 * Changed configurable variables to be consumed from a YAML file instead of json, it requires new installation

### Installer Actions
 * Update `deployex-config.json` to `deployex.yaml` to support new configuration. See examples at the [deployex-aws.yaml](https://github.com/thiagoesteves/deployex/blob/main/devops/installer/deployex-aws.yaml)
 * Update `deployex.sh` to be able to install using new configuration. `wget https://github.com/thiagoesteves/deployex/releases/download/0.4.0/deployex.sh`

### Bug fixes
 * None

### Enhancements
 * [[`PR-105`](https://github.com/thiagoesteves/deployex/pull/105)] Changing runtime load variables to use YAML file
 * Updated github actions to use ubuntu 24.04 and release deployex for OTP 26 and OTP 27
 * Updated Documentation

# Host Binaries Available

This release includes binaries for the following Ubuntu versions:

 * Ubuntu 24.04 with OTP 26 - [deployex-ubuntu-24.04-otp-26.tar.gz](https://github.com/thiagoesteves/deployex/tree/main/devops/releases/otp-26/.tool-versions)
 * Ubuntu 24.04 with OTP 27 - [deployex-ubuntu-24.04-otp-27.tar.gz](https://github.com/thiagoesteves/deployex/tree/main/devops/releases/otp-27/.tool-versions)

 You can use these pre-built binaries, or you can build your own if preferred.

# Previous Releases
 * [0.3.4 🚀 (2025-04-14)](https://github.com/thiagoesteves/deployex/blob/0.3.4/CHANGELOG.md)
 * [0.2.0 🚀 (2024-05-23)](https://github.com/thiagoesteves/deployex/blob/0.2.0/CHANGELOG.md)
 * [0.1.0 🚀 (2024-05-06)](https://github.com/thiagoesteves/deployex/blob/0.1.0/changelog.md)