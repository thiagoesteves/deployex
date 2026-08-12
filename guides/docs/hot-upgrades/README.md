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

## Good practices for a project that can be hot-upgraded

None of this is required to deploy.
It is what makes the difference between a release that can be hot-upgraded and one that has to restart.

**Build both versions with the same Erlang and Elixir.**
A hot upgrade replaces application code inside the running VM, it cannot replace the runtime underneath it.
If the two releases were built with different Elixir versions, `systools` asks for an appup that upgrades Elixir itself, which nobody ships:

```bash
[error] systools:make_relup failed for myphoenixapp 0.4.0 -> 0.4.2, reason: Could not open
file /var/lib/deployex/service/myphoenixapp/myphoenixapp-4pvclf/current/lib/elixir-1.20.3/ebin/elixir.appup
```

Pin the toolchain in `.tool-versions` and keep it identical across the two builds.
Bumping Erlang or Elixir is a full deployment, not a hot upgrade.

**Change your own code, not your dependencies.**
Every application whose version changes needs an appup, and each one is real code being swapped inside a live node.
[Jellyfish][jyf] generates them, but generating an appup is not the same as knowing the dependency survives being replaced under load.
Group dependency bumps into a release you deploy fully, and keep hot upgrades for your own code.

**Never hold an anonymous function across an upgrade.**
A function value is tied to the version of the module that created it.
Once that module is replaced the value is dead, and calling it raises:

```bash
** (BadFunctionError) function #Function<0.17932506/0 in MyApp.Worker> is invalid,
likely because it points to an old version of the code
```

Store `{module, function, args}` and call it with `apply/3` instead, which resolves against whatever is loaded at the time.
This applies to anything that outlives the upgrade: GenServer state, ETS tables, `:persistent_term`, timers, and messages already sitting in a mailbox.

**Keep functions out of your configuration.**
Application environment is written to `sys.config` and read back with `file:consult/1`, so every value has to be a term that can be written down and parsed again.
An anonymous function cannot, and a configuration file that fails to parse is silently replaced with an empty one, which resets the environment of every application in the release.
Use `&Module.fun/1` captures of exported functions, or plain data your code interprets.

**Give stateful processes a `code_change/3`.**
An appup can suspend a process, load the new module and resume it, but only your code knows how to reshape the state it was holding.
If a `GenServer` state changes shape between versions, write the migration.
If it does not, there is nothing to do.

**Give every build its own version.**
Upgrades are computed from one version to another, so two builds sharing a version cannot be told apart, and the appup has nothing to describe.

**Exercise the upgrade in CI.**
Build the current version, build the target, then apply one to the other against a real node before it reaches production.
This project does it in [`hot_upgrade.yaml`](/.github/workflows/hot_upgrade.yaml), and the [Calori project](https://github.com/thiagoesteves/calori/blob/main/.github/workflows/hot-upgrade.yaml) shows the same idea for a monitored application.

## Checking whether a hot upgrade is possible

**Compare the toolchains first.**
If the `.tool-versions` used for the two builds differ in Erlang or Elixir, stop here, it is a full deployment.

**Look for the upgrade metadata in the package.**
An Elixir release carries a `jellyfish.json` per application, an Erlang one carries `.appup` files:

```bash
tar -tzf myphoenixapp-1.1.0.tar.gz | grep -E "jellyfish.json|[.]appup$"
```

Nothing listed means the release was built without hot-upgrade information and can only be deployed fully.

**Check the versions it claims to upgrade from.**
Extract a `jellyfish.json` and read its `from` and `to`.
The `from` has to be the version currently running, which the Applications page shows, so a release built against an older version is not applicable no matter how well formed it is.

**Let DeployEx answer for you.**
For a monitored application the decision is made at deployment time and written to the log:

```bash
[warning] HOT UPGRADE version DETECTED - [%Deployer.HotUpgrade.Jellyfish{name: "myphoenixapp",
type: "project", from: "1.0.0", to: "1.1.0"}]
```

```bash
[warning] HOT UPGRADE version NOT DETECTED, full deployment required, reason: :not_found
```

`:not_found` means no metadata was found in the package, and `:no_match_versions` means it was found but describes a different starting version.

For DeployEx itself, uploading the file on the Hot-Upgrade page validates it before anything is applied, and the release is only offered for `Apply` once it passes.
That check refuses a package built for another OTP, and the reasons it can report are described in [Choosing the right release file](#choosing-the-right-release-file).

**Ask the node what it has installed.**
`:release_handler.which_releases()` lists the releases the node knows about and their status, which tells you what a previous attempt left behind:

```elixir
iex> :release_handler.which_releases()
...> |> Enum.map(fn {_name, vsn, _apps, status} -> {vsn, status} end)
[{~c"1.1.0", :permanent}, {~c"1.0.0", :old}]
```

A version left as `unpacked` is one a previous attempt started and did not install.

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

### Choosing the right release file

Each release publishes one artifact per OTP line, `deployex-ubuntu-24.04-otp-27.tar.gz` and `deployex-ubuntu-24.04-otp-28.tar.gz`.
The file has to match the `otp_version` the installation runs, which is the one in its `deployex.yaml`.
Picking the wrong one is the easiest way to hit the first entry in the list above, updating Erlang OTP, without meaning to.

A hot upgrade replaces application code inside the running VM, it cannot replace the VM or the language runtime underneath it.
A release built for another OTP brings a different Erlang and Elixir, and `systools:make_relup/4` needs an `.appup` for every application whose version changes, which neither ships.

The wrong file is refused while the release is validated, before anything is unpacked, naming the OTP the installation runs:

```bash
[error] Hot upgrade refused, this release was built for a different OTP. deployex runs
OTP 27 with erts 15.2.7.11 and the release brings erts 16.4.0.4. A hot upgrade cannot
replace the runtime under a running system. Use the artifact matching the otp_version
this installation runs, or apply it as a full deployment.
```

### When a hot upgrade fails

DeployEx does not fall back to a full deployment for itself.
It keeps running and logs why the upgrade stopped:

```bash
[error] Hot upgrade in deployex failed, 0.9.0 -> 0.9.1, reason: :make_relup.
Nothing was installed, deployex is still running 0.9.0.
```

The reason `systools` reports is included in that message, and the release unpacked by the attempt is unregistered, so the same version can be applied again once the cause is fixed.

Everything up to installing the release only writes files and builds the relup, so a failure there leaves the node running exactly the code it had, which is what `Nothing was installed` reports.
Past that point the new code is already loaded, and the message says so instead.

> [!NOTE]
> The UI applies the upgrade asynchronously, so the log records that it started and the outcome follows on a later line.
> The progress modal shows the result as it happens.
> The installer script applies it synchronously, so there `Hot upgrade in deployex installed with success` is written once the upgrade has actually finished.


## Hot-Upgrading Monitored Applications

Example GitHub CI workflow for hot-upgrading applications:

1. Fetch `current.json` to identify deployed version
2. Checkout current version and compile
3. Checkout target version and compile
4. Generate release with hot-upgrade information

See [example workflow](https://github.com/thiagoesteves/calori/blob/main/.github/workflows/hot-upgrade.yaml) for implementation details.

### When a hot upgrade fails

A release only reaches the hot upgrade path when it shipped the `.appup` or `jellyfish.json` files saying it supports one.
What DeployEx does when that upgrade fails depends on whether the running node was already changed.

If it failed before the release was installed, nothing on the node was touched, so there is nothing to recover and no reason to restart it.
The version is ghosted and the application carries on serving what it already runs:

```bash
[error] Hot upgrade failed before the release was installed at sname: myphoenixapp-63wu32,
reason: :make_relup. myphoenixapp is still running 1.0.0, ghosting version 1.1.0.
```

A ghosted version is skipped by every following deployment, so the same broken release is not attempted again.
Publish a new version once the cause is fixed, the application is not stuck waiting for it.

The application card on the Applications page shows the last ghosted version, and `View all` opens the full list.
From there a single version or all of them can be removed, which makes the engine offer them again on its next check.
That is the way to retry a version that was ghosted for a reason that no longer applies.

If the release was already installed and a later step failed, the node is running code that was never made permanent.
There DeployEx does fall back to a full deployment, which restarts the instance on the new version:

```bash
[error] Hot Upgrade failed, running for full deployment
```

# Additional Resources

- [Jellyfish Documentation][jyf] - AppUp file generation
- [Calori Project](https://github.com/thiagoesteves/calori) - Real-world implementation examples

[jyf]: https://github.com/user/jellyfish