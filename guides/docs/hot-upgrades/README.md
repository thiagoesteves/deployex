# 🔥 Hot-Upgrades

A hot upgrade replaces the code of a running system without restarting it.
Processes keep the state they were holding, connections stay open, and nothing is drained or rerouted.
What it cannot replace is the VM and the language runtime underneath that code, and that single limit decides most of what follows.

DeployEx applies hot upgrades to the applications it monitors and to itself.
It uses [Jellyfish][jyf] to generate the appup files automatically, which you can also write or extend by hand when an upgrade needs actions that cannot be inferred from the diff.

Most releases do not need a full deployment.
You do not change OTP or your libraries often, and a hot upgrade combines with migrations to ship a change with no downtime at all.
High availability is not free though, it is something you design for, and this guide covers the part of that design that shows up at deployment time.

A release is easiest to judge backwards: look first for what cannot be hot-upgraded, then decide about everything else.

## What can be hot-upgraded

 * **Monitored applications** - your deployed Elixir/Erlang/Gleam applications.
 * **Dependencies** - the libraries those applications use, once you have checked that the versions you are moving between can be replaced in a running node.
 * **DeployEx itself** - without restarting the deployment system.

Erlang/OTP and Elixir are never in scope.
They are the runtime the upgrade runs on rather than libraries loaded into it, so a release that changes either is a full deployment.
This is stated once here and is the reason behind several of the rules below.

Dependencies are versioned independently from the project, so DeployEx reports them separately, with `type: "dependency"` rather than `type: "project"`.

## When NOT to hot-upgrade

**DO NOT HOT-UPGRADE if:**
 * The new release is updating Erlang OTP
 * The new release is updating Elixir version
 * The new release modified/deleted/added config_provider files

The first two are the runtime limit above, and they are the same limit rather than two.
Erlang and Elixir are both replaced from underneath the running code, and `systools` asks for an appup that upgrades them, which nobody ships.
Picking a release artifact built for another OTP line is the easiest way to hit this by accident, see [Choosing the right release file](#choosing-the-right-release-file), and a mismatched Elixir is what produces the `make_relup` error in [Good practices](#good-practices-for-a-project-that-can-be-hot-upgraded).
The third is about configuration, which behaves differently from the rest of the release and is worth understanding rather than memorising.

**A changed `runtime.exs` is not on that list.** DeployEx resolves the new version's file and applies the result during the install, so those changes do take effect.
It has one condition attached, which the next section covers: the file is evaluated by the code the running node has loaded.

### What happens to configuration during a hot-upgrade

`runtime.exs` and the Config Providers only run when an application boots, so DeployEx resolves them itself over the RPC channel and applies the result during the install.
Understanding the order matters, because it decides which of your configuration changes actually take effect.

`release_handler:install_release/2` first rebuilds the environment of **every** loaded application from the new `.app` files and the new build time `sys.config`, and only then runs the relup instructions.
DeployEx adds a hook at the head of that relup which applies the resolved configuration, so the environment is complete before any process is suspended or has its code changed.

What that means in practice:

 * **Changed or removed keys are applied.** The environment is deleted and rebuilt, not merged, so a key you delete in the new version is really gone after the upgrade.
 * **A changed `runtime.exs` is applied.** DeployEx reads the new version's file, which `unpack_release/1` has already written to disk, so the values the application ends up with are the ones the new file resolves. The one condition is that it runs on the node as it is now: it is evaluated by the code the running node has loaded, so it must not rely on modules, functions or language features that only arrive with the new release. A `runtime.exs` that reads environment variables, files or secrets is fine. One that calls into a module the new version introduces is not, and that is the case to deploy fully.
 * **A changed Config Provider is NOT applied.** Provider modules run on the node in its current version, before the new code is installed, so the old implementation is what resolves the configuration. A fix to a provider only takes effect once a full deployment has made it the running version.

The last point is the reason for the `config_provider` entry in the list above, and it applies to the provider's own code, not to the values it produces.

## How a hot upgrade works

You do not need to write any of these files by hand, but knowing what they are is what makes the failures readable.

**The pieces**

 * An **appup** describes how to move one application from one version to another: which modules to load, which processes to suspend, and where to call `code_change/3`. [Jellyfish][jyf] generates one per application, as `jellyfish.json` for Elixir releases and `.appup` files for Erlang ones.
 * A **relup** is the plan for the whole release, built by `systools:make_relup/4` from the two releases and their appups. It is ordered, and it fails to build when an application changes version without an appup to describe how.
 * `release_handler` is the OTP module that runs that plan on the live node.

**The steps DeployEx runs over RPC on the running node**

1. `release_handler:unpack_release/1` registers the new release and puts its code on disk. Nothing is loaded yet.
2. `systools:make_relup/4` builds the plan. DeployEx inserts the resolved runtime configuration hook at its head.
3. `release_handler:check_install_release/1` evaluates the plan without applying it.
4. `release_handler:install_release/2` rebuilds the application environments and then runs the plan. From this point the node is running the new code.
5. `release_handler:make_permanent/1` makes the new version the one the node boots into next time.

Everything up to step 4 only writes files and computes, so a failure there leaves the node running exactly the code it had.
That distinction is what the failure messages report, and what decides whether DeployEx has anything to recover from.

**What happens to your processes**

For each changed module the plan loads the new code, and for a stateful process it suspends the process, calls `code_change/3`, then resumes it.
The process is never restarted and never loses its mailbox, it is paused for as long as the migration of its own state takes.
Everything that follows in [Good practices](#good-practices-for-a-project-that-can-be-hot-upgraded) is about making sure the code holding that state can survive being replaced underneath it.

### Which version performs the upgrade

A hot upgrade is carried out by the code already running, not by the code in the package.
DeployEx unpacks the release, builds the relup and installs it using the version currently installed, and only afterwards is the new code in charge.

That has one consequence worth remembering whenever a release fixes something in the hot upgrade path itself: the fix applies to upgrades performed **from** that version, not to the upgrade **into** it.
Going from a version with the bug to a version with the fix still runs the bug, because the buggy code is what does the work.

So when a release changes how hot upgrades behave, check its changelog before hot-upgrading into it.
Where that matters the release says so under `Backwards incompatible changes`, and the answer there is to apply it as a full deployment once, after which hot upgrades carry on normally.

The same applies to a monitored application whose own upgrade instructions changed, its `.appup` is executed by the release being replaced.

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

**Assess every dependency you upgrade, one at a time.**
Dependencies can be hot-upgraded, [Jellyfish][jyf] generates their appups the same way it does for your own applications.
An appup only describes how to load the new code though, it says nothing about whether that library survives being replaced under load, so each one is a decision rather than a default.

> [!WARNING]
> Before performing a hot-upgrade for any dependency, treat it with the same caution as your own application code.
> Check if the dependency officially supports hot-upgrades between the specific versions you're upgrading, review the changelog for breaking changes or structural modifications (e.g., process state changes, supervision tree changes, API changes), and pay special attention to stateful processes like GenServers, Agents, and ETS tables that may require special handling or coordinated state migration.

Do that per dependency, not per release, and keep the number moving in a single hot upgrade small enough that the review stays realistic.

Reading a dependency diff is worth handing to an LLM.
Ask it to summarise what changed between the two versions and, specifically, whether anything there affects state held by a running process or the shape of a supervision tree.
Treat the answer as a place to start looking, not as the verdict, and confirm what it reports against the changelog and the diff itself.

**Do not let an anonymous function outlive the call that created it.**
A function value is tied to the version of the module that built it.
Once that module is replaced the value is dead, and calling it raises:

```bash
** (BadFunctionError) function #Function<0.17932506/0 in MyApp.Worker> is invalid,
likely because it points to an old version of the code
```

This is about lifetime, not about anonymous functions being risky in themselves.
Almost all of them are fine, and rewriting them would make the code worse for no gain.

Fine, the value is created and used within the same call, so no upgrade can land between the two:

```elixir
def totals(entries) do
  entries
  |> Enum.filter(fn entry -> entry.status == :running end)
  |> Enum.map(& &1.size)
end

def report(entries) do
  render = fn entry -> "#{entry.name} #{entry.size}" end
  Enum.map_join(entries, "\n", render)
end
```

A problem, the value is stored and called later, and later can be after an upgrade:

```elixir
# in GenServer state
{:ok, %{on_complete: fn result -> notify(result) end}}

# in a message the process will handle afterwards
send(self(), {:finished, fn -> cleanup(path) end})

# handed to something that runs for a while
Downloader.stream(url, on_progress: fn pct -> broadcast(pct) end)
```

Store `{module, function, args}` in those places and reach it with `apply/3`, which resolves against whatever is loaded at the time.

Ask one question about a function value: **can this still be called after the current call returns?**
If it can, it needs to be an MFA.
The places where the answer is yes are GenServer state, ETS tables, `:persistent_term`, timers, messages already sitting in a mailbox, and callbacks handed to something long-running such as a download or a stream.

Captures have the same lifetime rule.
`&Module.fun/1` of a public function is as safe as an MFA, since it is resolved through the module.
`&private_fun/1` and `&(&1 + n)` are closures over the current module version and are not.

**Let long-running processes re-enter their loop through the module.**
The VM keeps two versions of a module, the current one and the old one, and a process that is executing old code stays there until it makes a fully qualified call.
Load a third version and the old code is purged, taking any process still lingering in it with it.

OTP behaviours do this for you, since `GenServer`, `Supervisor` and friends invoke your callbacks through the module on every message, so a `GenServer` is on the new code as soon as the upgrade completes.
A hand written process is not:

```elixir
# stays in old code forever, and dies at the next purge
defp loop(state) do
  receive do
    msg -> loop(handle(state, msg))
  end
end

# picks up the new code on the next message
defp loop(state) do
  receive do
    msg -> __MODULE__.loop(handle(state, msg))
  end
end
```

The same applies to anything that runs for a long time inside one call, a `Task` looping over a queue or a stream consumed over hours.
It keeps running the code it started with, and there is no supported way to change that from the outside.
Write those as behaviours, or make the loop re-enter through the module so an upgrade has a point at which to take effect.

**Give stateful processes a `code_change/3`.**
An appup can suspend a process, load the new module and resume it, but only your code knows how to reshape the state it was holding.
If a `GenServer` state changes shape between versions, write the migration.
If it does not, there is nothing to do.

**Treat a supervision tree change as a step of its own.**
An upgrade changes code, it does not change the shape of the running system, so a server you added is not started and one you removed is not stopped.
This is the one case where the generated appup is not enough on its own, and it has a section of its own below, [Adding or removing a process in the supervision tree](#adding-or-removing-a-process-in-the-supervision-tree).

**Keep functions out of your configuration.**
Application environment is written to `sys.config` and read back with `file:consult/1`, so every value has to be a term that can be written down and parsed again.
An anonymous function cannot, and a configuration file that fails to parse is silently replaced with an empty one, which resets the environment of every application in the release.
Use `&Module.fun/1` captures of exported functions, or plain data your code interprets.

**Keep the two versions compatible at their boundaries.**
For a while the old and the new version coexist: messages sent before the upgrade are handled after it, replicas are upgraded one at a time so they talk to each other across versions, and rows and ETS entries written by the old code are read by the new one.
Anything crossing those boundaries has to be readable by both, which makes the usual expand then contract sequence the safe shape.
The release that adds a field accepts both shapes, and the release that drops the old one comes after it.

**Do not hot-upgrade native code.**
A dependency that loads a NIF or a port driver brings a shared object that the VM loads outside the normal code path, and replacing it in a live node has rules of its own.
Unless the library documents support for it, move those versions with a full deployment.

**Give every build its own version.**
Upgrades are computed from one version to another, so two builds sharing a version cannot be told apart, and the appup has nothing to describe.

**Exercise the upgrade before production.**
Build the current version, build the target, then apply one to the other against a real node.
The local guides walk through exactly that on a machine, see [Local-Elixir](/guides/docs/local-elixir/README.md), and it belongs in CI afterwards.
This project does it in [`hot_upgrade.yaml`](/.github/workflows/hot_upgrade.yaml), and the [Calori project](https://github.com/thiagoesteves/calori/blob/main/.github/workflows/hot-upgrade.yaml) shows the same idea for a monitored application.

## Adding or removing a process in the supervision tree

A hot upgrade replaces code, it does not restructure the running system.
When a release adds a child to a supervisor, or removes one, the upgrade alone does not act on it:

 * A server you **added** is not started. Its module is loaded, its child specification is recorded, and nothing runs it.
 * A server you **removed** is not stopped. It keeps running, on the old code, until the node restarts.

That is `{update, Module, supervisor}` doing what it is defined to do.
It loads the new supervisor module and re-reads `init/1`, so the restart strategy and the child specifications the supervisor knows about are the new ones, but the children that are already running are left exactly as they are.

**Jellyfish cannot generate this for you.**
It builds the appup by comparing the compiled modules of the two versions, so it sees that a module was added, changed or deleted.
A child specification lives inside `init/1`, which is data the comparison cannot reach, so no start or terminate instruction is generated.
Nothing fails at build time and nothing fails during the upgrade either, the release installs cleanly and the new server simply is not there afterwards, which is the reason this one is worth knowing before it happens rather than after.

**What the appup needs.**
The instructions to add are `apply` ones, calling the supervisor API directly.
An appup is `{NewVersion, [{FromVersion, UpInstructions}], [{FromVersion, DownInstructions}]}`, and adding a child looks like this:

```erlang
{"1.1.0",
 [{"1.0.0", [
    {add_module, 'Elixir.MyApp.Cache'},
    {update, 'Elixir.MyApp.Supervisor', supervisor},
    {apply, {supervisor, restart_child, ['Elixir.MyApp.Supervisor', 'Elixir.MyApp.Cache']}}
  ]}],
 [{"1.0.0", [
    {apply, {supervisor, terminate_child, ['Elixir.MyApp.Supervisor', 'Elixir.MyApp.Cache']}},
    {apply, {supervisor, delete_child, ['Elixir.MyApp.Supervisor', 'Elixir.MyApp.Cache']}},
    {update, 'Elixir.MyApp.Supervisor', supervisor},
    {delete_module, 'Elixir.MyApp.Cache'}
  ]}]
}.
```

Removing a child is the same list the other way round, terminate and delete the child, update the supervisor, then delete the module.
Order is the part to get right: the module has to be loaded before a child using it is started, and the child has to be stopped before its module is deleted.
`supervisor:restart_child/2` is what starts a child the supervisor knows about but is not running, which is exactly the state `{update, Module, supervisor}` leaves a newly added specification in.

**Where to edit it.**
[Jellyfish][jyf] can pause the release so you can edit the file it just generated:

```bash
EDIT_APPUP=true MIX_ENV=prod mix release
# Press any key when you're done editing rel/appups/myphoenixapp/1.0.0_to_1.1.0.appup
```

The other way is to untar the release, edit `lib/<app>-<vsn>/ebin/<app>.appup`, and tar it again.
Either way, keep the downgrade list consistent with the upgrade one, and remember that the appup is executed by the version being replaced, see [Which version performs the upgrade](#which-version-performs-the-upgrade).

**Writing those instructions is a good task to hand to an LLM.**
Give it the `init/1` of the supervisor in both versions and the appup Jellyfish generated, and ask it to add the instructions for the children that appeared or disappeared, in the correct order.
It is a mechanical translation from a diff into a known instruction set, which is the kind of work it does well.
Read the result yourself before shipping it, the same way you would read the diff of a dependency: check the order, check that the child ids match the ones in `init/1`, and check the downgrade list.
Then apply the upgrade against a real node and confirm the tree, `Supervisor.which_children/1` tells you what actually runs after it.

The alternative is always available and sometimes the better trade: ship the tree change as a full deployment, and keep the hot upgrades for changes that only touch code.

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
For a `"project"` entry the `from` has to be the version currently running, which the Applications page shows, so a release built against an older version is not applicable no matter how well formed it is.
A `"dependency"` entry carries the library's own versions instead, since dependencies are versioned independently from the project.

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
Picking the wrong one is the easiest way to hit the first entry of [When NOT to hot-upgrade](#when-not-to-hot-upgrade), updating Erlang OTP, without meaning to.

A hot upgrade replaces application code inside the running VM, it cannot replace the VM or the language runtime underneath it.
A release built for another OTP brings a different Erlang and Elixir, and `systools:make_relup/4` needs an `.appup` for every application whose version changes, which neither ships.

The wrong file is refused while the release is validated, before anything is unpacked, naming the OTP the installation runs:

```bash
[error] Hot upgrade refused, this release was built for a different OTP. deployex runs
OTP 27 with erts 15.2.7.11 and the release brings erts 16.4.0.4. A hot upgrade cannot
replace the runtime under a running system. Use the artifact matching the otp_version
this installation runs, or apply it as a full deployment.
```

### When a DeployEx upgrade fails

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

Two things about the rollout are worth knowing before you rely on it.

**Migrations run before the upgrade, from the new version.**
The pre-commands declared in `current.json` are executed against the release that was just unpacked, before any code is installed, which is what lets a schema change and the code that needs it ship together without downtime.
The consequence is the ordinary one for online migrations: while they run, the code serving traffic is still the old version, so the migration has to be one the old code survives.

**Replicas are upgraded one at a time.**
Each deployment cycle upgrades a single instance and then moves to the next, so a release is rolled across the replicas rather than applied to all of them at once.
During that window some replicas run the new version and some the old, which is the boundary compatibility rule from the good practices above.

### When a monitored application upgrade fails

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

## Going back

There is no hot downgrade.
A relup can describe the way back, but DeployEx does not generate or apply one, and a release that turns out to be wrong is undone the same way any other bad release is: publish the previous version and let it deploy fully.

That is worth knowing while deciding, because it makes the two directions asymmetric.
The upgrade avoids downtime, the way back does not.
The more of your release that is state living inside processes, the more that asymmetry should push you towards being conservative about what goes into a hot upgrade at all.

## Glossary

| Term | What it is |
| --- | --- |
| `appup` | Per application upgrade instructions, from one version to another. Generated by [Jellyfish][jyf] as `jellyfish.json`, or written by hand as `.appup`. |
| `relup` | The ordered plan for the whole release, built by `systools:make_relup/4` from two releases and their appups. |
| `release_handler` | The OTP module that unpacks, installs and makes a release permanent on a live node. |
| `unpacked` | Release status. The code is on disk and registered, nothing is loaded. |
| `current` | Release status. Installed and running, but not yet the one the node would boot into. |
| `permanent` | Release status. Installed and the one the node boots into next time. |
| `old` | Release status. A previously permanent release that has been replaced. |
| ghosted version | A version DeployEx has marked as not to be deployed again after it failed, skipped by later deployment checks until it is removed. |

## Additional Resources

- [Jellyfish Documentation][jyf] - AppUp file generation
- [Erlang OTP Design Principles: Release Handling](https://www.erlang.org/doc/system/release_handling.html) - what `release_handler` does and in what order
- [Erlang Appup Cookbook](https://www.erlang.org/doc/system/appup_cookbook.html) - worked appups, including supervisors and special processes
- [Erlang Compilation and Code Loading](https://www.erlang.org/doc/system/code_loading.html) - current and old code, purging, fully qualified calls
- [Calori Project](https://github.com/thiagoesteves/calori) - Real-world implementation examples

[jyf]: https://github.com/thiagoesteves/jellyfish
