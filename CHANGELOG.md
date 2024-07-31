# Changelog for version v0.3.0

## 0.3.0-rc13 ()

## Backwards incompatible changes for 0.3.0-rc12
 * A new folder was created (`storage`) and this will represent the persistent data for deployex, updating to this version will require losing previous data.

### Bug fixes
 * None

### Enhancements
 * [[``]()] 

## 0.3.0-rc12 (2024-07-29)

## Backwards incompatible changes for 0.3.0-rc11
 * None

### Bug fixes
 * None

### Enhancements
 * [[`PR-19`](https://github.com/thiagoesteves/deployex/pull/19)] Adding backoff delay pattern for retries and enhanced Monitor state handling
 * [[`32ac1b9`](https://github.com/thiagoesteves/deployex/commit/32ac1b9debdd7eff5f11aeb833b1616ae6d3f7e7)] Adding ability to copy/paste for the IEX terminal

## 0.3.0-rc11 (2024-07-09)

## Backwards incompatible changes for 0.3.0-rc10
 * Modified aws secret manager name which requires an update from the previous version
 * Modified installer script to use a configuration json file instead arguments

### Bug fixes
 * None

### Enhancements
 * [[`PR-21`](https://github.com/thiagoesteves/deployex/pull/21/files)] Modified aws secret manager name to deployex-${deployex_monitored_app_name}-${deployex_cloud_environment}-secrets
 * Modified ubuntu installer script to require a configuration json file instead of arguments

## 0.3.0-rc10 (2024-07-02)

## Backwards incompatible changes for 0.3.0-rc9
 * None

### Bug fixes
 * [[`PR-16`](https://github.com/thiagoesteves/deployex/pull/16)] Fixed an uptime bug that at deployex.

### Enhancements
 * [[`PR-18`](https://github.com/thiagoesteves/deployex/pull/18/files)] Improvements for consistency

## 0.3.0-rc9 (2024-06-27)

## Backwards incompatible changes for 0.3.0-rc8
 * None

### Bug fixes
 * [[`c9bdc47`](https://github.com/thiagoesteves/deployex/commit/c9bdc47)] Fixed an uptime bug that incorrectly depended on previous version information.

### Enhancements
 * [[`769e69f`](https://github.com/thiagoesteves/deployex/commit/769e69f)] Created an installer script for ubuntu and added it to the release package

## 0.3.0-rc8 (2024-06-26)

## Backwards incompatible changes for 0.3.0-rc7
 * None

### Bug fixes
 * None

### Enhancements
 * Modifying form ids for terminal/logs

## 0.3.0-rc7 (2024-06-26)

## Backwards incompatible changes for 0.3.0-rc6
 * None

### Bug fixes
 * None

### Enhancements
 * Modifying log view to keep the scroll position at the bottom

## 0.3.0-rc6 (2024-06-25)

## Backwards incompatible changes for 0.3.0-rc5
 * None

### Bug fixes
 * None

### Enhancements
 * Adding stderr log file for deployex

## 0.3.0-rc5 (2024-06-24)

## Backwards incompatible changes for 0.3.0-rc4
 * None

### Bug fixes
 * None

### Enhancements
 * Adding possibility to connect to the IEX terminal (including deployex)

## 0.3.0-rc4 (2024-06-10)

## Backwards incompatible changes for 0.3.0-rc3
 * None

### Bug fixes
 * None

### Enhancements
 * Adding stderr and stdout logs for each app from liveview (including deployex)

## 0.3.0-rc3 (2024-06-02)

## Backwards incompatible changes for 0.3.0-rc2
 * None

### Bug fixes
 * None

### Enhancements
 * Improved version badge and uptime status show
 * Fixed app card click

## 0.3.0-rc2 (2024-06-01)

## Backwards incompatible changes for 0.3.0-rc1
 * None

### Bug fixes
 * Fixing exception when clicking in the app button

### Enhancements
 * Adding try/catch for calling Monitor GenServer
 * Adding uptime feature for monitored apps.

## 0.3.0-rc1 (2024-05-29)

## Backwards incompatible changes for 0.2.1-rc1
 * This version requires new environment variables to be defined. Please ensure the following environment variables are set.

### Bug fixes
 * None

### Enhancements
 * Modified the application to be able to handle multiple instances for the monitored app

# Host Binaries Available

This release includes binaries for the following Ubuntu versions:

 * Ubuntu 20.04
 * Ubuntu 22.04

 You can use these pre-built binaries, or you can build your own if preferred.

# Previous Releases
 * [0.2.0 🚀 (2024-05-23)](https://github.com/thiagoesteves/deployex/blob/0.2.0/CHANGELOG.md)
 * [0.1.0 🚀 (2024-05-06)](https://github.com/thiagoesteves/deployex/blob/0.1.0/changelog.md)