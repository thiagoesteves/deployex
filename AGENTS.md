# DeployEx - Agent Code Guide

## Project Overview

DeployEx is an Elixir **umbrella application** that manages deployments for BEAM applications (Elixir, Erlang, Gleam).
It monitors running nodes, performs full deployments and hot upgrades, manages TLS certificates, sends notifications, and exposes a Phoenix LiveView dashboard.
It does **not** use Docker or Kubernetes - it relies purely on OTP distribution.

The project version lives in `mix/shared.exs` (`Mix.Shared.version/0`) - do not hardcode it elsewhere.
Elixir requirement is `~> 1.16`; the exact toolchain is pinned in `.tool-versions` (Erlang 28.5.0.2, Elixir 1.19.5-otp-28).

---

## Umbrella Structure

```
apps/
  foundation/       # Core config, accounts, catalog, certificates, notifications, RPC, YAML parsing
  deployer/         # Release management, deployment engine, hot upgrades
  sentinel/         # Log streaming and watchdog monitoring
  host/             # Host system info, command execution, terminal sessions (tmux)
  deployex_web/     # Phoenix + LiveView web interface
mix/
  shared.exs        # Shared version, Elixir requirement, test coverage config used by all apps
devops/
  installer/        # Installer scripts
  releases/         # Per-OTP release configs (otp-27/, otp-28/ with their own .tool-versions)
  scripts/          # Operational scripts
```

Module naming follows the app prefix: `Foundation.*`, `Deployer.*`, `Sentinel.*`, `Host.*`, `DeployexWeb.*`.

---

## Development Commands

```bash
# Install deps and compile (warnings as errors)
mix do deps.get + compile --warnings-as-errors

# Run locally (needs a named node for OTP distribution)
iex --sname deployex --cookie cookie -S mix phx.server

# Run all tests with coverage
mix test --cover --warnings-as-errors

# Format code
mix format

# Check formatting (CI gate)
mix format --check-formatted

# Credo lint (strict mode)
mix credo --strict

# Check unused dependencies
mix deps.unlock --check-unused

# Dialyzer type checking
mix dialyzer

# Security audit
mix deps.audit
mix sobelow -r apps/deployex_web --exit --threshold medium --skip -i Config.HTTPS

# Generate docs
mix docs
```

Local runtime configuration comes from `deployex.yaml` at the repo root.
In production the path is provided via the `DEPLOYEX_CONFIG_YAML_PATH` environment variable.

---

## Safety and Permissions

Rules for AI agents about which actions may run without asking and which require explicit confirmation first.

**Allowed without asking:**

- Reading and listing files anywhere in the repository
- Compiling the project (`mix compile`)
- Formatting or format-checking specific files (`mix format <files>`)
- Linting (`mix credo`)
- Running a single test file or a focused subset (e.g. `mix test apps/<app>/test/<file>.exs`)

**Ask first:**

- Installing or updating packages (changing `mix.exs` deps, `mix deps.get` / `mix deps.update` after dependency changes)
- `git push` or any other action that leaves the local machine
- Deleting files or changing permissions (`rm`, `chmod`)
- Running the full test suite with coverage, `mix dialyzer`, or other long/expensive whole-project runs
- Building or running releases (`mix release`), or starting the app against real nodes

---

## Testing

- **Framework:** ExUnit - each app has its own `test/` directory and `test_helper.exs`
- **Test support:** `test/support/` per app; includes mocks, stubs, fixture helpers
- **Mocking:** `Mox` (behaviour-based) and `Mock` (module-level) - adapters in test env are all mocked (e.g. `Deployer.ReleaseMock`, `Foundation.RpcMock`)
- **Coverage threshold:** **94%** - enforced in CI via `mix test --cover`
- **Excluded modules:** Application callbacks, Adapter behaviours, Supervisor modules, and fixture helpers are excluded from coverage (see `ignore_modules` in `mix/shared.exs`)

When adding a new module, check if it needs to be added to the `ignore_modules` list in `mix/shared.exs` if it can't be reasonably unit-tested (Application, Supervisor, Adapter behaviour definitions).

---

## Code Patterns

### Adapter Pattern
Behaviour modules with a `Mock` counterpart for testing:
```
Deployer.Release.Adapter       # behaviour
Deployer.ReleaseMock           # Mox mock used in tests
```
Adapters are configured via `config/test.exs` for the test environment.

### GenServer Pattern
Stateful processes (monitors, catalog trackers, hot-upgrade servers) use GenServer.
Follow existing naming: `Module.Server` for the GenServer, `Module.Supervisor` for its supervisor.

### Phoenix LiveView
All real-time UI pages use LiveView.
Component files live under `apps/deployex_web/lib/deployex_web/live/`.

### Config Provider Pattern
`Foundation.ConfigProvider.Env.Config` and `Foundation.ConfigProvider.Secrets.Manager` are used in releases to inject configuration at runtime.

### PubSub
`Phoenix.PubSub` is used for broadcasting state changes.
Broadcast from business logic apps; subscribe from LiveView components.

---

## Code Preferences

Prescriptive rules for writing new code in this project.

- **Prefer supervised GenServers over ad-hoc concurrency.**
  Any long-lived, stateful, or background process must be a `GenServer` under a supervision tree.
  Do not use `Task.start/async`, `Agent`, or bare `spawn` for background work - the codebase intentionally has zero of them.
- **Dynamically created processes go under a `DynamicSupervisor`** (see `Deployer.Monitor.Supervisor`, `Host.Terminal.Supervisor`).
- **Follow the naming convention:** `Module.Server` for the GenServer, `Module.Supervisor` for its supervisor.
- **Periodic or delayed work:** schedule with `Process.send_after(self(), msg, timeout)` handled in `handle_info/2`, not sleeping processes or interval Tasks.
- **Non-blocking reads:** when other processes need frequent access to a GenServer's state, mirror it into a protected named ETS table owned by that GenServer (see `Deployer.Monitor.Application`, `Sentinel.Watchdog`).
- **Cross-process/app communication:** broadcast via `Phoenix.PubSub` with well-defined message tuples; avoid calling into another app's internals directly.
- **External integrations** (cloud storage, RPC, OS commands) go behind an Adapter behaviour with a Mox mock, so business logic stays testable.

---

## Commit Message Style

Use **imperative mood**, **sentence case**, PR number at the end:

```
Add on-the-fly notification config and change events to strings (#233)
Remove Certificate GenServer, call initializer directly from Application (#232)
CloudFlare integration (#226)
Preparing the release
```

- Start with a verb: Add, Remove, Fix, Update, Refactor, Move
- Keep subject line concise (under ~72 chars)
- Reference the PR number `(#NNN)` when merging a feature branch

---

## Pull Requests

### Branch naming

Branches are named `{github-user}/feature-or-bugfix-name`, e.g. `thiagoesteves/fix-stderr-log-streaming`.

### PR checklist

Before opening a PR, confirm every item:

- [ ] Title follows `feat(scope): short description` (also `fix`, `refactor`, `docs`, `test`, `chore`)
- [ ] All checks green locally before committing: `mix format --check-formatted`, `mix credo --strict`, and the unit tests for the affected apps (plus `mix dialyzer` when specs or types changed)
- [ ] Diff is small and focused on one change; unrelated cleanups go in their own PR
- [ ] Description briefly summarizes what changed and why
- [ ] Excessive logs, debug output (`IO.inspect`, `dbg`), and leftover comments removed
- [ ] Risk assessment included (see below)

### Risk assessment

Every PR description must include a **Risk assessment** section with:

- **Impact:** what changes for users/operators when this ships
- **Blast radius:** which modules/apps are touched and which are guaranteed untouched
- **Regression risk:** low/medium/high, with the reasoning
- **Rollback:** how to revert (plain commit revert, or data/config steps if any)

Also include the risk assessment in the commit message body so it survives outside GitHub.
For bug fixes, state how the bug was reproduced (ideally a test that fails without the fix).

When a PR is authored by an AI agent, credit it at the end of the description with:
`🤖 Generated with [Claude Code](https://claude.com/claude-code)`
Never add the agent as commit co-author.

---

## CI/CD (GitHub Actions)

All PRs target `main` and must pass `.github/workflows/pr-ci.yaml`:

| Step | Command |
|---|---|
| Compile | `mix do deps.get + compile --warnings-as-errors` |
| Tests + coverage | `mix test --cover --warnings-as-errors` |
| Unused deps | `mix deps.unlock --check-unused` |
| Credo | `mix credo --strict` |
| Docs | `mix docs --failed` |
| Dependency audit | `mix deps.audit` |
| Security | `mix sobelow -r apps/deployex_web --exit --threshold medium --skip -i Config.HTTPS` |
| Formatting | `mix format --check-formatted` |
| Dialyzer | `mix dialyzer --format github` |

Other workflows: `releases.yaml` (release builds), `hot_upgrade.yaml` (hot upgrade testing), `testing-release.yaml` (release testing).

---

## Code Quality Rules

- **Max line length:** 120 characters (enforced by Credo)
- **Max nesting depth:** 3 levels
- **No tabs** - spaces only
- Credo runs in `--strict` mode; fix all warnings before merging
- Dialyzer PLT lives at `priv/plts/dialyzer.plt`
- All compiler warnings are treated as errors in CI

---

## Key Dependencies

Exact versions are in `mix.lock`; do not trust version numbers written in docs.

| Library | Purpose |
|---|---|
| phoenix / phoenix_live_view | Web framework and real-time UI |
| bandit | HTTP server |
| jellyfish | Hot upgrade support (release step `Jellyfish.generate/1`) |
| ex_aws / ex_aws_s3 / ex_aws_acm | AWS integration |
| goth | GCP authentication |
| yaml_elixir | YAML config parsing |
| x509 / ex_acme | TLS certificate management |
| mox / mock | Test mocking |
| observer_web | OTP process observability |
| tailwind / esbuild | Frontend assets |

---

## Release

Releases are built via `mix release`.
The `release` alias runs a `digest_docs` pre-step, and the release steps are `:assemble`, `Jellyfish.generate/1`, `:tar`.
The release name is `deployex`.
CI builds artifacts for both OTP-27 and OTP-28 using the `.tool-versions` files under `devops/releases/otp-27/` and `devops/releases/otp-28/`.

The release pipeline is in `.github/workflows/releases.yaml`.
Hot upgrade testing has its own workflow: `.github/workflows/hot_upgrade.yaml`.

---

## Changelog Maintenance

`CHANGELOG.md` is maintained manually.
After a PR is merged, add an entry for it to the top (unreleased) version section, e.g. `## 0.9.5 ()`.

Rules:

- Place the entry under the matching category: `### Bug fixes`, `### Enhancements`, or `### Backwards incompatible changes`
- Entry format (one line, PR title as the description):
  `* [`PULL-NNN`](https://github.com/thiagoesteves/deployex/pull/NNN) <PR title>`
- For issues, use `ISSUE-NNN` with the `/issues/NNN` URL instead
- Keep entries sorted by ascending PR number within each category
- Replace the `* None` placeholder when adding the first entry to a category; keep `* None` in empty categories
- Backwards incompatible changes also describe the required operator steps (installer commands, hotupgrade caveats), see the `0.9.2` and `0.9.0` sections for examples
- The release date and rocket emoji are added to the heading only when the version ships: `## 0.9.4 🚀 (2026-06-22)`, unreleased versions keep an empty date: `## 0.9.5 ()`

---

## Release Preparation

To prepare a release, open a single "prepare release" PR that applies all of the following:

1. `mix/shared.exs`: set the final version, without the `-rcN` suffix (e.g. `"0.9.5-rc1"` -> `"0.9.5"`)
2. `README.md`: in the version compatibility table, remove the `:soon:` marker from the released version row and make sure the OTP columns match the Erlang versions pinned in `devops/releases/otp-*/.tool-versions`
3. `devops/installer/deployex-aws.yaml` and `devops/installer/deployex-gcp.yaml`: set `version:` to the released version
4. `guides/docs/yaml/README.md`: set the `version:` field in the YAML example to the released version
5. `CHANGELOG.md`: add the release date to the version heading in the format `## X.Y.Z 🚀 (YYYY-MM-DD)`
6. Run `mix docs` to regenerate the published documentation (commits the updated `apps/deployex_web/priv/static/docs/docs.tar.gz`)

After the PR is merged, pushing the version tag from main triggers `.github/workflows/releases.yaml` to build and publish the release artifacts.

---

## Guides and Documentation

- `guides/docs/` - deployment guides per cloud/language (AWS-Elixir, GCP-Elixir, Local-Erlang, etc.)
- `guides/docs/hot-upgrades/` - hot upgrade documentation
- `guides/docs/yaml/` - YAML configuration reference
- `CHANGELOG.md` - version history, updated manually per merged PR (see "Changelog Maintenance")
- Docs are generated with `mix docs` and published into `apps/deployex_web/priv/static/docs/`
