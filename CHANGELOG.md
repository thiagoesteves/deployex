# CHANGELOG (0.9.X)

## 0.9.13 ()

### Backwards incompatible changes from 0.9.12
 * [`PULL-292`](https://github.com/thiagoesteves/deployex/pull/292) The DeployEx `monitoring` entries are now only evaluated when configured. Previously a DeployEx instance with no `memory` entry in the top level `monitoring` section still had its host memory checked against the built-in 75%/90% defaults with restart enabled. Add an explicit `- type: "memory"` entry to `deployex.yaml` to keep that protection.

### Bug fixes
 * [`PULL-288`](https://github.com/thiagoesteves/deployex/pull/288) Report a deployment as complete only when one has finished, not on a hot upgrade or an application restart
 * [`PULL-289`](https://github.com/thiagoesteves/deployex/pull/289) Mark a deployment in flight explicitly instead of inferring it, so the completion notification is not missed

### Enhancements
 * [`PULL-288`](https://github.com/thiagoesteves/deployex/pull/288) Report the versions a hot upgrade moved between in the completion notification
 * [`PULL-290`](https://github.com/thiagoesteves/deployex/pull/290) Add an application_ready event for every report that an application is running
 * [`PULL-292`](https://github.com/thiagoesteves/deployex/pull/292) Monitor the DeployEx atom, process and port limits alongside the host memory
 * [`PULL-293`](https://github.com/thiagoesteves/deployex/pull/293) Show the URLs each connected application is serving on, read from its own endpoints
 * [`PULL-296`](https://github.com/thiagoesteves/deployex/pull/296) Replace the Elixir and Erlang logos with the official ones and swap to a brighter variant on dark themes
 * [`PULL-305`](https://github.com/thiagoesteves/deployex/pull/305) Fetch the logo from the `<name>_web` child when the monitored application is a Phoenix umbrella

## 0.9.12 🚀 (2026-08-12)

### Backwards incompatible changes from 0.9.11
 * Hot upgrade from `0.9.11` is supported. Applications using `storage_options` need one extra step afterwards, since a running certificate manager keeps the state it started with: comment the `certificates` section out of `deployex.yaml` and apply the change, then uncomment it and apply again. That restarts the manager with the fix from [`PULL-286`](https://github.com/thiagoesteves/deployex/pull/286).

### Bug fixes
 * [`PULL-286`](https://github.com/thiagoesteves/deployex/pull/286) Carry the certificate storage_options into the certificate manager so renewals are written to disk

### Enhancements
 * None

## 0.9.11 🚀 (2026-08-12)

### Backwards incompatible changes from 0.9.10
 * Apply this release as a full deployment, do not hot-upgrade from `0.9.10`. A hot upgrade is performed by the version already installed, so the fixes in [`PULL-278`](https://github.com/thiagoesteves/deployex/pull/278) and [`PULL-280`](https://github.com/thiagoesteves/deployex/pull/280) only take effect from `0.9.11` onwards. Hot upgrades between later versions behave normally.

### Bug fixes
 * [`PULL-272`](https://github.com/thiagoesteves/deployex/pull/272) Refuse a DeployEx hot upgrade built for a different OTP
 * [`PULL-273`](https://github.com/thiagoesteves/deployex/pull/273) Remove the unpacked release left behind by a failed hot upgrade
 * [`PULL-274`](https://github.com/thiagoesteves/deployex/pull/274) Stop reporting a DeployEx hot upgrade as successful before it has run
 * [`PULL-275`](https://github.com/thiagoesteves/deployex/pull/275) Refuse a file that is not a DeployEx release instead of crashing the upload
 * [`PULL-276`](https://github.com/thiagoesteves/deployex/pull/276) Ghost the version instead of forcing a full deployment when a hot upgrade never installed the release
 * [`PULL-278`](https://github.com/thiagoesteves/deployex/pull/278) Stop the failed hot upgrade cleanup from deleting the running release libraries
 * [`PULL-280`](https://github.com/thiagoesteves/deployex/pull/280) Record the version after a DeployEx self upgrade through an MFA, not a captured function
 * [`PULL-283`](https://github.com/thiagoesteves/deployex/pull/283) Apply the FinchStream download callbacks through an MFA instead of a captured function
 * [`PULL-284`](https://github.com/thiagoesteves/deployex/pull/284) Show why a release downloaded from GitHub was refused in the download panel

### Enhancements
 * [`PULL-277`](https://github.com/thiagoesteves/deployex/pull/277) Add a ghosted version list to the UI with clear all and clear one actions
 * [`PULL-281`](https://github.com/thiagoesteves/deployex/pull/281) Document the good practices for a hot-upgradeable project and how to check a release
 * [`PULL-282`](https://github.com/thiagoesteves/deployex/pull/282) Add the checks for deciding whether the next version supports hot upgrade to AGENTS.md

## 0.9.10 🚀 (2026-08-10)

### Backwards incompatible changes from 0.9.9
 * None

### Bug fixes
 * [`PULL-265`](https://github.com/thiagoesteves/deployex/pull/265) Stop password managers filling credentials into the GitHub artifact form
 * [`PULL-267`](https://github.com/thiagoesteves/deployex/pull/267) Correct the hot upgrade confirmation, it does not terminate anything

### Enhancements
 * [`PULL-268`](https://github.com/thiagoesteves/deployex/pull/268) Automate TLS certificates and move the deployment guides to Debian 13
 * [`PULL-269`](https://github.com/thiagoesteves/deployex/pull/269) Write renewed certificates to disk

## 0.9.9 🚀 (2026-08-07)

### Backwards incompatible changes from 0.9.8
 * None - version `0.9.9` supports hot upgrade from `0.9.8`

### Bug fixes
 * [`PULL-261`](https://github.com/thiagoesteves/deployex/pull/261) Fail the upgrade when a config provider does not return a configuration
 * [`PULL-263`](https://github.com/thiagoesteves/deployex/pull/263) Apply the runtime configuration through a relup hook instead of sys.config

### Enhancements
 * None

## 0.9.8 🚀 (2026-08-06)

### Backwards incompatible changes from 0.9.7

#### Installer Actions
 1. It's not mandatory, but it's recommended to update `deployex.sh` so new installations pick up the hardened systemd service and the needrestart exclusion.
 ```bash
 rm deployex.sh
 wget https://github.com/thiagoesteves/deployex/releases/download/0.9.8/deployex.sh
 chmod a+x deployex.sh
 ./deployex.sh --update
 ```
 2. `--update` does not rewrite `/etc/systemd/system/deployex.service`, so an existing installation keeps its current unit and none of the service changes from [`PULL-254`](https://github.com/thiagoesteves/deployex/pull/254) take effect. Running `--install` recreates the unit, but it also removes `/var/lib/deployex` and the monitored application logs first. To keep the installation intact, apply the new `KillMode`, `TimeoutStopSec` and `OOMPolicy` settings to the existing unit by hand and reload systemd.
 ```bash
 systemctl daemon-reload
 systemctl restart deployex
 ```

### Bug fixes
 * [`PULL-254`](https://github.com/thiagoesteves/deployex/pull/254) Stop left-over processes in the control group and unattended needrestart restarts
 * [`PULL-256`](https://github.com/thiagoesteves/deployex/pull/256) Write the needrestart exclusion even when needrestart is absent

### Enhancements
 * [`PULL-252`](https://github.com/thiagoesteves/deployex/pull/252) Update OTP to 27.3.4.15 and 28.5.0.4
 * [`PULL-253`](https://github.com/thiagoesteves/deployex/pull/253) Update library dependencies
 * [`PULL-255`](https://github.com/thiagoesteves/deployex/pull/255) Add copy button next to the application version

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