# CHANGELOG (v0.3.0)

## 0.3.0 🚀 (2025-01-06)

### Backwards incompatible changes for 0.2.0
 * Changed adapters/secrets to be configurable, new variables documentation added to the README.
 * Added new configuration for google credentials when using GCP, new variables documentation added to the README.
 * Changed storage to use term files instead jason format, updating to this version will require losing previous data.

### Installer Actions
 * Update `deployex-config.json` to support new configuration
 * Update `deployex.sh` to be able to install using new configuration

### Bug fixes
 * [[`PR-69`](https://github.com/thiagoesteves/deployex/pull/69)] Fixed bug that was rendering mode set when not required
 * [[`PR-62`](https://github.com/thiagoesteves/deployex/pull/62)] Modified application index to handle only its own node monitoring data
 * [[`PR-63`](https://github.com/thiagoesteves/deployex/pull/63)] Fixed blocking state for Monitor GenServer, when migrations were too long, the system couldn't fetch its state anymore. It is now under an ETS table and can be accessed without going to the Monitor GenServer.
 * [[`PR-60`](https://github.com/thiagoesteves/deployex/pull/60)] Fixed issues with auto-complete functionality in the IEx terminal and increased the log and terminal size.
 * [[`PR-59`](https://github.com/thiagoesteves/deployex/pull/59)] Fixing bug that was capturing letter v as Ctrl+v.
 * [[`PR-51`](https://github.com/thiagoesteves/deployex/pull/51)] Terminal copy/paste bug, terminal was pasting when copying code within it.
 * [[`Issue-47`](https://github.com/thiagoesteves/deployex/issues/47)] Application logs were not being appended
 * [[`PR-16`](https://github.com/thiagoesteves/deployex/pull/16)] Fixed an uptime bug that at deployex.
 * [[`c9bdc47`](https://github.com/thiagoesteves/deployex/commit/c9bdc47)] Fixed an uptime bug that incorrectly depended on previous version information.
 * Fixing exception when clicking in the app button

### Enhancements
 * [[`PR-92`](https://github.com/thiagoesteves/deployex/pull/92)] Adding System Info bar to Applications and Live Tracing
 * [[`PR-83`](https://github.com/thiagoesteves/deployex/pull/83)] Adding Live logs option
 * [[`PR-84`](https://github.com/thiagoesteves/deployex/pull/84)] Refactoring Terminal Server
 * [[`PR-86`](https://github.com/thiagoesteves/deployex/pull/86)] Adding Live Observer option
 * [[`PR-88`](https://github.com/thiagoesteves/deployex/pull/88)] Adding Live Tracing option
 * [[`PR-91`](https://github.com/thiagoesteves/deployex/pull/91)] Updated liveview and OTP to 26.2.5.6
 * [[`PR-77`](https://github.com/thiagoesteves/deployex/pull/77)] Adding Erlang support
 * [[`PR-80`](https://github.com/thiagoesteves/deployex/pull/80)] Adding Erlang hot upgrade support
 * [[`PR-82`](https://github.com/thiagoesteves/deployex/pull/82)] Adding host Terminal (tmux) via Liveview
 * [[`PR-70`](https://github.com/thiagoesteves/deployex/pull/70)] Changed function listener to subscribe
 * [[`PR-71`](https://github.com/thiagoesteves/deployex/pull/71)] Added ex_docs and enhanced documentation
 * [[`PR-72`](https://github.com/thiagoesteves/deployex/pull/72)] Change deploy reference to string instead erlang reference
 * [[`PR-73`](https://github.com/thiagoesteves/deployex/pull/73)] Adding deploy_ref to the monitor global_name
 * [[`PR-75`](https://github.com/thiagoesteves/deployex/pull/75)] Adding Gleam support
 * [[`PR-58`](https://github.com/thiagoesteves/deployex/pull/58)] Updated terminal to allow more than one connection since authentication is required.
 * [[`PR-44`](https://github.com/thiagoesteves/deployex/pull/44)] New storage format (term), allowing a better map handling
 * [[`PR-49`](https://github.com/thiagoesteves/deployex/pull/49)] Adding authentication scheme
 * [[`PR-50`](https://github.com/thiagoesteves/deployex/pull/50)] Since authentication is required, there is noneed of typing the Erlang cookie
 * [[`PR-43`](https://github.com/thiagoesteves/deployex/pull/43)] New mode set functionality, the user can now set a specific version to be applied.
 * Multiple optimizations and improvements in organizations and context
 * Unit test added to achieve 100% of coverage
 * [[`00eb09f`](https://github.com/thiagoesteves/deployex/commit/00eb09f71e4ea25ef6a062edade9c95380fda74b)] Modify Monitor to use dynamic supervisors for start/stop instead of receiving direct commands via gen_server
 * [[`b91f640`](https://github.com/thiagoesteves/deployex/commit/b91f640a78a375ddfff310e1465ac962480dc7ee)] Implemented pre_commands functionality for running migrations
 * [[`PR-19`](https://github.com/thiagoesteves/deployex/pull/19)] Adding backoff delay pattern for retries and enhanced Monitor state handling
 * [[`32ac1b9`](https://github.com/thiagoesteves/deployex/commit/32ac1b9debdd7eff5f11aeb833b1616ae6d3f7e7)] Adding ability to copy/paste for the IEX terminal
 * [[`PR-21`](https://github.com/thiagoesteves/deployex/pull/21/files)] Modified aws secret manager name to deployex-${deployex_monitored_app_name}-${deployex_cloud_environment}-secrets
 * Modified ubuntu installer script to require a configuration json file instead of arguments
 * [[`PR-18`](https://github.com/thiagoesteves/deployex/pull/18/files)] Improvements for consistency
 * [[`769e69f`](https://github.com/thiagoesteves/deployex/commit/769e69f)] Created an installer script for ubuntu and added it to the release package
 * Modifying log view to keep the scroll position at the bottom
 * Adding stderr log file for deployex
 * Adding possibility to connect to the IEX terminal (including deployex)
 * Adding stderr and stdout logs for each app from liveview (including deployex)
 * Improved version badge and uptime status show
 * Fixed app card click
 * Adding try/catch for calling Monitor GenServer
 * Adding uptime feature for monitored apps.
 * Modified the application to be able to handle multiple instances for the monitored app

# Host Binaries Available

This release includes binaries for the following Ubuntu versions:

 * Ubuntu 20.04
 * Ubuntu 22.04

 You can use these pre-built binaries, or you can build your own if preferred.

# Previous Releases
 * [0.2.0 🚀 (2024-05-23)](https://github.com/thiagoesteves/deployex/blob/0.2.0/CHANGELOG.md)
 * [0.1.0 🚀 (2024-05-06)](https://github.com/thiagoesteves/deployex/blob/0.1.0/changelog.md)