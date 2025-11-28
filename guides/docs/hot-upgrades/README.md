# 🔥 Hot-Upgrades

DeployEx supports hot-upgrades for both monitored applications and DeployEx itself. There are many considerations before using hot-upgrades, and the decision of when to apply them is up to each project. DeployEx uses [Jellyfish][jyf] to generate appup files automatically, which can be modified or created manually if you want to add more actions. Sometimes it's better to start by looking at what you cannot hot-upgrade, then analyze the other changes in the release. The `Jellyfish + DeployEx` package has some limitations that may change over time, so stay tuned for these recommendations.

**DO NOT HOT-UPGRADE if:**
 * The new release is updating Elixir and/or Erlang OTP
 * The new release is updating/adding/removing libraries (there is a feature in progress in Jellyfish for updating specific libraries)
 * The new release changed the `runtime.exs` file
 * The new release changed config_provider files

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
./deployex.sh --hot-upgrade /tmp/deployex-0.8.1-rc2.tar.gz /tmp/deployex.yaml

# Executing hot upgrade via RPC            #
# Release file: /tmp/hotupgrade/download/deployex-0.8.1-rc2.tar.gz

11:21:30.373 [info] deployex hot upgrade requested: 0.8.1-rc1 -> 0.8.1-rc2

11:21:42.745 [warning] Hot upgrade in deployex installed with success
# Hot upgrade completed successfully       #
```
### Method 2: UI/UX Release Upload

Use the DeployEx web interface:

1. Open the Hot-Upgrade page in DeployEx
2. Upload the release file (DeployEx automatically validates the release)
3. Click Apply
4. Monitor the progress modal until the hot-upgrade completes successfully

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