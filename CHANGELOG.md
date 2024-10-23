# CHANGELOG (v0.3.0)

## 0.3.0-rc21 (2024-10-23)

### Backwards incompatible changes for 0.3.0-rc20
 * Added new configuration for gleam, new variables documentation added to the README.

### Installer Actions
 * Update `deployex-config.json` to support new configuration
 * Update `deployex.sh` to be able to install using new configuration

### Bug fixes
 * None

### Enhancements
 * [[`PR-70`](https://github.com/thiagoesteves/deployex/pull/70)] Changed function listener to subscribe
 * [[`PR-71`](https://github.com/thiagoesteves/deployex/pull/71)] Added ex_docs and enhanced documentation
 * [[`PR-72`](https://github.com/thiagoesteves/deployex/pull/72)] Change deploy reference to string instead erlang reference
 * [[`PR-73`](https://github.com/thiagoesteves/deployex/pull/73)] Adding deploy_ref to the monitor global_name
 * [[`PR-75`](https://github.com/thiagoesteves/deployex/pull/75)] Adding Gleam support

## 0.3.0-rc20 (2024-10-02)

### Backwards incompatible changes for 0.3.0-rc19
 * None

### Installer Actions
 * None

### Bug fixes
 * [[`PR-69`](https://github.com/thiagoesteves/deployex/pull/69)] Fixed bug that was rendering mode set when not required

## 0.3.0-rc19 (2024-09-26)

### Backwards incompatible changes for 0.3.0-rc18
 * None

### Installer Actions
 * None

### Bug fixes
 * [[`PR-62`](https://github.com/thiagoesteves/deployex/pull/62)] Modified application index to handle only its own node monitoring data
 * [[`PR-63`](https://github.com/thiagoesteves/deployex/pull/63)] Fixed blocking state for Monitor GenServer, when migrations were too long, the system couldn't fetch its state anymore. It is now under an ETS table and can be accessed without going to the Monitor GenServer.

## 0.3.0-rc18 (2024-09-20)

### Backwards incompatible changes for 0.3.0-rc17
 * A sew set of env vars were introduced in the installer, it requires update.

### Installer Actions
 * Update `deployex.sh` to be able to install using new configuration

### Bug fixes
 * [[`PR-60`](https://github.com/thiagoesteves/deployex/pull/60)] Fixed issues with auto-complete functionality in the IEx terminal and increased the log and terminal size.

## 0.3.0-rc17 (2024-09-16)

### Backwards incompatible changes for 0.3.0-rc16
 * None

### Installer Actions
 * None

### Bug fixes
 * [[`PR-59`](https://github.com/thiagoesteves/deployex/pull/59)] Fixing bug that was capturing letter v as Ctrl+v.

## 0.3.0-rc16 (2024-09-13)

### Backwards incompatible changes for 0.3.0-rc15
 * None

### Installer Actions
 * None

### Bug fixes
 * None

### Enhancements
 * [[`PR-58`](https://github.com/thiagoesteves/deployex/pull/58)] Updated terminal to allow more than one connection since authentication is required.

## 0.3.0-rc15 (2024-09-12)

### Backwards incompatible changes for 0.3.0-rc14
 * Changed release adapter to be configurable (adapter and bucket), new variables documentation added to the README.
 * Created secrets adapter (adapter and path) to be able to configure different formats of fetching secrets, new variables documentation added to the README.
 * Added new configuration for google credentials when using GCP, new variables documentation added to the README.

### Installer Actions
 * Update `deployex-config.json` to support new configuration
 * Update `deployex.sh` to be able to install using new configuration

### Bug fixes
 * [[`PR-51`](https://github.com/thiagoesteves/deployex/pull/51)] Terminal copy/paste bug, terminal was pasting when copying code within it.

### Enhancements
 * None

## 0.3.0-rc14 (2024-09-03)

### Backwards incompatible changes for 0.3.0-rc13
 * Changed storage to use term files instead jason format, updating to this version will require losing previous data.
 * New secret needs to be set to allow authentication __DEPLOYEX_ADMIN_HASHED_PASSWORD__

### Bug fixes
 * [[`Issue-47`](https://github.com/thiagoesteves/deployex/issues/47)] Application logs were not being appended

### Enhancements
 * [[`PR-44`](https://github.com/thiagoesteves/deployex/pull/44)] New storage format (term), allowing a better map handling
 * [[`PR-49`](https://github.com/thiagoesteves/deployex/pull/49)] Adding authentication scheme
 * [[`PR-50`](https://github.com/thiagoesteves/deployex/pull/50)] Since authentication is required, there is noneed of typing the Erlang cookie
 * [[`PR-43`](https://github.com/thiagoesteves/deployex/pull/43)] New mode set functionality, the user can now set a specific version to be applied.
 * Multiple optimizations and improvements in organizations and context
 * Unit test added to achieve >90% of coverage

## 0.3.0-rc13 (2024-08-02)

### Backwards incompatible changes for 0.3.0-rc12
 * A new folder was created (`storage/{app-name}`) and this will represent the persistent data for deployex, updating to this version will require losing previous data.

### Bug fixes
 * None

### Enhancements
 * [[`00eb09f`](https://github.com/thiagoesteves/deployex/commit/00eb09f71e4ea25ef6a062edade9c95380fda74b)] Modify Monitor to use dynamic supervisors for start/stop instead of receiving direct commands via gen_server
 * [[`b91f640`](https://github.com/thiagoesteves/deployex/commit/b91f640a78a375ddfff310e1465ac962480dc7ee)] Implemented pre_commands functionality for running migrations

## 0.3.0-rc12 (2024-07-29)

### Backwards incompatible changes for 0.3.0-rc11
 * None

### Bug fixes
 * None

### Enhancements
 * [[`PR-19`](https://github.com/thiagoesteves/deployex/pull/19)] Adding backoff delay pattern for retries and enhanced Monitor state handling
 * [[`32ac1b9`](https://github.com/thiagoesteves/deployex/commit/32ac1b9debdd7eff5f11aeb833b1616ae6d3f7e7)] Adding ability to copy/paste for the IEX terminal

## 0.3.0-rc11 (2024-07-09)

### Backwards incompatible changes for 0.3.0-rc10
 * Modified aws secret manager name which requires an update from the previous version
 * Modified installer script to use a configuration json file instead arguments

### Bug fixes
 * None

### Enhancements
 * [[`PR-21`](https://github.com/thiagoesteves/deployex/pull/21/files)] Modified aws secret manager name to deployex-${deployex_monitored_app_name}-${deployex_cloud_environment}-secrets
 * Modified ubuntu installer script to require a configuration json file instead of arguments

## 0.3.0-rc10 (2024-07-02)

### Backwards incompatible changes for 0.3.0-rc9
 * None

### Bug fixes
 * [[`PR-16`](https://github.com/thiagoesteves/deployex/pull/16)] Fixed an uptime bug that at deployex.

### Enhancements
 * [[`PR-18`](https://github.com/thiagoesteves/deployex/pull/18/files)] Improvements for consistency

## 0.3.0-rc9 (2024-06-27)

### Backwards incompatible changes for 0.3.0-rc8
 * None

### Bug fixes
 * [[`c9bdc47`](https://github.com/thiagoesteves/deployex/commit/c9bdc47)] Fixed an uptime bug that incorrectly depended on previous version information.

### Enhancements
 * [[`769e69f`](https://github.com/thiagoesteves/deployex/commit/769e69f)] Created an installer script for ubuntu and added it to the release package

## 0.3.0-rc8 (2024-06-26)

### Backwards incompatible changes for 0.3.0-rc7
 * None

### Bug fixes
 * None

### Enhancements
 * Modifying form ids for terminal/logs

## 0.3.0-rc7 (2024-06-26)

### Backwards incompatible changes for 0.3.0-rc6
 * None

### Bug fixes
 * None

### Enhancements
 * Modifying log view to keep the scroll position at the bottom

## 0.3.0-rc6 (2024-06-25)

### Backwards incompatible changes for 0.3.0-rc5
 * None

### Bug fixes
 * None

### Enhancements
 * Adding stderr log file for deployex

## 0.3.0-rc5 (2024-06-24)

### Backwards incompatible changes for 0.3.0-rc4
 * None

### Bug fixes
 * None

### Enhancements
 * Adding possibility to connect to the IEX terminal (including deployex)

## 0.3.0-rc4 (2024-06-10)

### Backwards incompatible changes for 0.3.0-rc3
 * None

### Bug fixes
 * None

### Enhancements
 * Adding stderr and stdout logs for each app from liveview (including deployex)

## 0.3.0-rc3 (2024-06-02)

### Backwards incompatible changes for 0.3.0-rc2
 * None

### Bug fixes
 * None

### Enhancements
 * Improved version badge and uptime status show
 * Fixed app card click

## 0.3.0-rc2 (2024-06-01)

### Backwards incompatible changes for 0.3.0-rc1
 * None

### Bug fixes
 * Fixing exception when clicking in the app button

### Enhancements
 * Adding try/catch for calling Monitor GenServer
 * Adding uptime feature for monitored apps.

## 0.3.0-rc1 (2024-05-29)

### Backwards incompatible changes for 0.2.1-rc1
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