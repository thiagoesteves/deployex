# CHANGELOG (0.8.X)


## 0.8.1 ()

### Backwards incompatible changes for 0.8.0

### Installer Actions
 1. It’s not mandatory, but it’s recommended to update `deployex.sh` so it can support custom installation, hotupgrades and changing folder for log directories.
 ```bash
 rm deployex.sh
 wget https://github.com/thiagoesteves/deployex/releases/download/0.8.1/deployex.sh
 chmod a+x deployex.sh
 ./deployex.sh --install
 ```

### Bug fixes
 * None

### Enhancements
 * [`ISSUE-188`](https://github.com/thiagoesteves/deployex/issues/188) Add DeployEx Secrets via environment vars
 * [`PULL-189`](https://github.com/thiagoesteves/deployex/pull/189) Adding hot upgrade functionality for DeployEx itself via CLI

## 0.8.0 🚀 (2025-11-20)

### Backwards incompatible changes for 0.7.3

### Installer Actions
 1. Update `deployex.yaml` file, moving the variables `deploy_timeout_rollback_ms` and `deploy_timeout_rollback_ms` to each application instead of defining them globally.

**Before (0.8.0 and earlier):**
```yaml
deploy_rollback_timeout_ms: 600000
deploy_schedule_interval_ms: 5000
applications:
  - name: "myphoenixapp"
    language: "elixir"
```
**After (0.8.0):**
```yaml
applications:
  - name: "myphoenixapp"
    language: "elixir"
    deploy_rollback_timeout_ms: 600000
    deploy_schedule_interval_ms: 5000
```
 2. Download `deployex.sh` to support installation using the new configuration format. The logs directory has changed from `/var/log/{monitored_app_name}` to `/var/log/monitored-apps/{monitored_app_name}`, which means you will need to update your log collector (e.g., CloudWatch).
 ```bash
 rm deployex.sh
 wget https://github.com/thiagoesteves/deployex/releases/download/0.8.0/deployex.sh
 chmod a+x deployex.sh
 ./deployex.sh --install
 ```

### Bug fixes
 * [`PULL-174`](https://github.com/thiagoesteves/deployex/pull/174) Fixing truncated logs for Live and History logs dashboard
 * [`PULL-175`](https://github.com/thiagoesteves/deployex/pull/175) Adding log details in live applications stdout/stderr
 * [`PULL-181`](https://github.com/thiagoesteves/deployex/pull/181) Fixes GCP service account credentials config

### Enhancements
 * [`ISSUE-167`](https://github.com/thiagoesteves/deployex/issues/167) Modify Deployer app to re-load the yaml and apply changes
 * [`PULL-171`](https://github.com/thiagoesteves/deployex/pull/171) Adding monitoring data view in UX/UI
 * [`PULL-177`](https://github.com/thiagoesteves/deployex/pull/177) Adding configurable log retention period
 * [`PULL-180`](https://github.com/thiagoesteves/deployex/pull/180) Moving deploy timeouts to be handle by application and not globally
 * [`PULL-182`](https://github.com/thiagoesteves/deployex/pull/182) Adding app config information in the UI/UX and full restart button for all apps
 * [`PULL-186`](https://github.com/thiagoesteves/deployex/pull/186) Adding host uptime to UI/UX
 * [`PULL-187`](https://github.com/thiagoesteves/deployex/pull/187) Update DeployEx to elixir 1.19.3

# Host Binaries Available

This release includes binaries for the following Ubuntu versions:

 * Ubuntu 24.04 with OTP 27 - [deployex-ubuntu-24.04-otp-27.tar.gz](https://github.com/thiagoesteves/deployex/tree/main/devops/releases/otp-27/.tool-versions)
 * Ubuntu 24.04 with OTP 28 - [deployex-ubuntu-24.04-otp-28.tar.gz](https://github.com/thiagoesteves/deployex/tree/main/devops/releases/otp-28/.tool-versions)

 You can use these pre-built binaries, or you can build your own if preferred.

# Previous Releases
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