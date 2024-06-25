# Changelog

## 0.3.0-rc6 ()

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

## 0.2.1-rc1 (2024-05-24)

## Backwards incompatible changes for 0.2.0
 * None

### Bug fixes
 * None

### Enhancements
 * Changed `env.sh.eex` to use environment variables for RELEASE_COOKIE and only set the default value if the ENV VAR is not present. 
 This will allow the remote connection to be able to capture the RELEASE_COOKIE from the environment

## 0.2.0 🚀 (2024-05-23)

This release marks a transformation of the application, transitioning it into a Phoenix LiveView app featuring a dashboard providing real-time status updates on the current deployment.

## Backwards incompatible changes for 0.1.0
 * This version requires new environment variables to be defined. Please ensure the following environment variables are set.

### Bug fixes
 * None

### Enhancements
 * Transitioning it into a Phoenix LiveView app featuring a dashboard providing real-time status updates on the current deployment.
 * Changed changelog.md to CHANGELOG.md

## 0.1.0 🚀 (2024-05-06)

Initial release for deployex

# Host Binaries Available

This release includes binaries for the following Ubuntu versions:

 * Ubuntu 20.04
 * Ubuntu 22.04

 You can use these pre-built binaries, or you can build your own if preferred.
