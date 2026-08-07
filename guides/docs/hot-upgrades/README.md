# 🔥 Hot-Upgrades

DeployEx supports hot-upgrades for both monitored applications and DeployEx itself. There are many considerations before using hot-upgrades, and the decision of when to apply them is up to each project. DeployEx uses [Jellyfish][jyf] to generate appup files automatically, which can be modified or created manually if you want to add more actions. Sometimes it's better to start by looking at what you cannot hot-upgrade, then analyze the other changes in the release. The `Jellyfish + DeployEx` package has some limitations that may change over time, so stay tuned for these recommendations.

**DO NOT HOT-UPGRADE if:**
 * The new release is updating Erlang OTP
 * The new release modified/deleted/added the `runtime.exs` file
 * The new release modified/deleted/added config_provider files

### What happens to configuration during a hot-upgrade

`runtime.exs` and the Config Providers only run when an application boots, so DeployEx resolves them itself over the RPC channel and applies the result during the install.
Understanding the order matters, because it decides which of your configuration changes actually take effect.

`release_handler:install_release/2` first rebuilds the environment of **every** loaded application from the new `.app` files and the new build time `sys.config`, and only then runs the relup instructions.
DeployEx adds a hook at the head of that relup which applies the resolved configuration, so the environment is complete before any process is suspended or has its code changed.

What that means in practice:

 * **Changed or removed keys are applied.** The environment is deleted and rebuilt, not merged, so a key you delete in the new version is really gone after the upgrade.
 * **A changed `runtime.exs` is applied.** DeployEx reads the new version's file, which has already been unpacked. It is evaluated by the code the running node has loaded, so it must not rely on modules or language features that only arrive with the new release.
 * **A changed Config Provider is NOT applied.** Provider modules run on the node in its current version, before the new code is installed, so the old implementation is what resolves the configuration. A fix to a provider only takes effect once a full deployment has made it the running version.

The last point is the reason for the `config_provider` entry in the list above, and it applies to the provider's own code, not to the values it produces.

> [!WARNING]
> [Jellyfish][jyf] allows you to hot-upgrade dependencies, but before performing a hot-upgrade for any dependency, treat it with the same caution as your own application code. Check if the dependency officially supports hot-upgrades between the specific versions you're upgrading, review the changelog for breaking changes or structural modifications (e.g., process state changes, supervision tree changes, API changes), and pay special attention to stateful processes like GenServers, Agents, and ETS tables that may require special handling or coordinated state migration.

Keep in mind that most of your releases will not require full deployment. You don't update OTP or libraries frequently, but you can combine hot-upgrades with migrations to avoid downtime, and much more. This topic is very vast, and we encourage you to apply and learn. High availability is a feature that doesn't come for free and require learning process.

## Hot-Upgrade Capabilities

Hot-upgrades can be applied to:
- **Monitored Applications** - Your deployed Elixir/Erlang/Gleam applications
- **DeployEx Itself** - The DeployEx system can hot-upgrade without restart

DeployEx uses [Jellyfish][jyf] to automatically generate appup files, which can be customized if needed.

## Hot-Upgrading DeployEx

To hot-upgrade DeployEx itself:

1. Check the [GitHub hot-upgrade workflow](/.github/workflows/hot_upgrade.yaml) for release creation
2. Review the Changelog to verify your current version supports upgrading to the target version

Then choose one of the following methods:

### Method 1: Installer Script

Use the installer script with a local release file:
```bash
./deployex.sh --hot-upgrade /tmp/deployex-0.9.1.tar.gz

# Executing hot upgrade via RPC            #
# Release file: /tmp/hotupgrade/download/deployex-0.9.1.tar.gz

11:21:30.373 [info] deployex hot upgrade requested: 0.9.0 -> 0.9.1

11:21:42.745 [warning] Hot upgrade in deployex installed with success
# Hot upgrade completed successfully       #
```

### Method 2: UI Release Upload

Use the DeployEx web interface to upload a release file:

1. Open the Hot-Upgrade page in DeployEx
2. Upload the release file (DeployEx automatically validates it)
3. Click **Apply**
4. Monitor the progress modal until the hot-upgrade completes successfully

### Method 3: GitHub Actions Release Download

Use the DeployEx web interface to download a release from GitHub:

1. Open the Hot-Upgrade page in DeployEx
2. Click **GitHub URL**
3. Enter the artifact URL
4. Enter your GitHub personal access token and click **Download** (DeployEx automatically validates the release)
5. Click **Apply**
6. Monitor the progress modal until the hot-upgrade completes successfully

## Hot-Upgrading Monitored Applications

Example GitHub CI workflow for hot-upgrading applications:

1. Fetch `current.json` to identify deployed version
2. Checkout current version and compile
3. Checkout target version and compile
4. Generate release with hot-upgrade information

See [example workflow](https://github.com/thiagoesteves/calori/blob/main/.github/workflows/hot-upgrade.yaml) for implementation details.

# Additional Resources

- [Jellyfish Documentation][jyf] - AppUp file generation
- [Calori Project](https://github.com/thiagoesteves/calori) - Real-world implementation examples

[jyf]: https://github.com/user/jellyfish