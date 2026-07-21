# CHANGELOG (0.9.X)

## 0.9.7 🚀 (2026-07-21)

### Backwards incompatible changes from 0.9.6
 * None - version `0.9.7` supports hot upgrade from `0.9.6`

### Bug fixes
 * None

### Enhancements
 * [`PULL-250`](https://github.com/thiagoesteves/deployex/pull/250) Updating ObserverWeb and adding new disclosure component

## 0.9.6 🚀 (2026-07-14)

### Backwards incompatible changes from 0.9.5
 * None

### Bug fixes
 * None

### Enhancements
 * [`PULL-249`](https://github.com/thiagoesteves/deployex/pull/249) Update Observer Web to 0.2.6 with its new logo in the nav menu, loading `:observer` and `:mnesia` to enable the crashdump viewer and Mnesia table browser

## 0.9.5 🚀 (2026-07-08)

### Backwards incompatible changes from 0.9.4
 * None

### Bug fixes
 * [`PULL-239`](https://github.com/thiagoesteves/deployex/pull/239) Fix engine state corruption on rollback timeout during initial boot
 * [`PULL-240`](https://github.com/thiagoesteves/deployex/pull/240) Fix read-after-write race in the web cache
 * [`PULL-241`](https://github.com/thiagoesteves/deployex/pull/241) Fix stderr log streaming from monitored applications
 * [`PULL-242`](https://github.com/thiagoesteves/deployex/pull/242) Make the engine worker resilient to restarts while monitors are running

### Enhancements
 * [`PULL-235`](https://github.com/thiagoesteves/deployex/pull/235) Update library dependencies
 * [`PULL-237`](https://github.com/thiagoesteves/deployex/pull/237) Add CloudWatch log group retention policy (terraform)
 * [`PULL-238`](https://github.com/thiagoesteves/deployex/pull/238) Updated observer web and packages
 * [`PULL-243`](https://github.com/thiagoesteves/deployex/pull/243) Adding agents.md file for tracking
 * [`PULL-245`](https://github.com/thiagoesteves/deployex/pull/245) Update actions/checkout from v5 to v7 in all workflows
 * [`PULL-246`](https://github.com/thiagoesteves/deployex/pull/246) Parametrize release workflows with an OTP matrix

## 0.9.4 🚀 (2026-06-22)

### Backwards incompatible changes from 0.9.3
 * None

### Bug fixes
 * None

### Enhancements
 * [`PULL-230`](https://github.com/thiagoesteves/deployex/pull/230) Add external alerting via Webhook, Slack, and PagerDuty notification adapters
 * [`PULL-232`](https://github.com/thiagoesteves/deployex/pull/232) Remove Certificate GenServer, call initializer directly from Application
 * [`PULL-233`](https://github.com/thiagoesteves/deployex/pull/233) Add on-the-fly notification config and change events to strings

## 0.9.3 🚀 (2026-06-17)

### Backwards incompatible changes from 0.9.2
 * None

### Bug fixes
 * None

### Enhancements
 * [`PULL-228`](https://github.com/thiagoesteves/deployex/pull/228) Add OTP/Elixir/Phoenix version info to monitored app status

## 0.9.2 🚀 (2026-06-15)

### Backwards incompatible changes from 0.9.1

#### Installer Actions
 1. It’s not mandatory, but it’s recommended to update `deployex.sh`.
 ```bash
 rm deployex.sh
 wget https://github.com/thiagoesteves/deployex/releases/download/0.9.2/deployex.sh
 chmod a+x deployex.sh
 ./deployex.sh --update
 ```

### Bug fixes
 * None

### Enhancements
 * [`PULL-220`](https://github.com/thiagoesteves/deployex/pull/220) Changing log level to INFO when running unit tests
 * [`PULL-216`](https://github.com/thiagoesteves/deployex/pull/216) Let's Encrypt Certificate Management for DeployEx
 * [`ISSUE-207`](https://github.com/thiagoesteves/deployex/issues/207) Increase the default timeout for IEX/ERL terminal
 * [`PULL-225`](https://github.com/thiagoesteves/deployex/pull/225) Cleaning up inet_tls.conf file before updating deployex application

## 0.9.1 🚀 (2026-05-15)

### Backwards incompatible changes from 0.9.0
 * None

### Bug fixes
 * [`PULL-217`](https://github.com/thiagoesteves/deployex/pull/217) Updating due to vulnerabilities

### Enhancements
 * None

## 0.9.0 🚀 (2026-04-01)

### Backwards incompatible changes from 0.8.0

#### Hotupgrade
 * Hotupgrade from 0.8.0 to 0.9.0 is not viable since the previous version doesn't support it.

#### Installer Actions
 1. It’s not mandatory, but it’s recommended to update `deployex.sh` so it can support custom installation, hotupgrades and changing folder for log directories.
 ```bash
 rm deployex.sh
 wget https://github.com/thiagoesteves/deployex/releases/download/0.9.1/deployex.sh
 chmod a+x deployex.sh
 ./deployex.sh --install
 ```

### Bug fixes
 * [`ISSUE-203`](https://github.com/thiagoesteves/deployex/issues/203) DeployEx restarted after Github returned 504
 * [`PULL-208`](https://github.com/thiagoesteves/deployex/pull/208) Disabling mouse on tmux due to issues between tmux and xterm

### Enhancements
 * [`ISSUE-188`](https://github.com/thiagoesteves/deployex/issues/188) Add DeployEx Secrets via environment vars
 * [`PULL-189`](https://github.com/thiagoesteves/deployex/pull/189) Adding hot upgrade functionality for DeployEx itself via CLI
 * [`PULL-193`](https://github.com/thiagoesteves/deployex/pull/193) Adding UI/UX for hotupgrading deployex itself
 * [`PULL-201`](https://github.com/thiagoesteves/deployex/pull/201) Adding support for hotupgrading libraries
 * [`PULL-211`](https://github.com/thiagoesteves/deployex/pull/211) Adding self-signed certificate generation depending on the OTP release
 * [`PULL-214`](https://github.com/thiagoesteves/deployex/pull/214) Adding mTLS information for checking the certificates and show in the UI

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