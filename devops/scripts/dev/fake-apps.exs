# Shows fake apps next to the real ones on a running `make start`, to look at the dashboard with many apps.
# `make dev-fake-apps` evaluates it on the DeployEx node with `count` bound, and `make dev-fake-apps-off`
# removes them. The fakes pass through `Deployer.Status` only: they run nothing, and their Logs, shell and
# Restart buttons act on instances that do not exist.

defmodule DevFakeApps.Fakes do
  @moduledoc false
  alias Deployer.Resources
  alias Deployer.Resources.Limit
  alias Deployer.Status

  @monitoring [
    atom: %{enable_restart: true, warning_threshold_percent: 75, restart_threshold_percent: 90},
    process: %{enable_restart: true, warning_threshold_percent: 75, restart_threshold_percent: 90},
    port: %{enable_restart: true, warning_threshold_percent: 75, restart_threshold_percent: 90}
  ]

  # Name, runtime, version, replicas and the state to show, so every state of the board is there
  @apps [
    {"billing_api", "elixir", "4.12.0", 3, deploy: :hot_upgrade, age: 2 * 3600},
    {"checkout", "elixir", "2.8.3", 2, age: 26 * 3600},
    {"notifications", "erlang", "1.4.0", 2, crash: 40 * 60, age: 5 * 3600},
    {"search_indexer", "elixir", "0.19.2", 1, process: 82, age: 3 * 86_400},
    {"auth_service", "elixir", "2.3.1", 2, pinned: "2.3.1", age: 9 * 86_400},
    {"payments_gateway", "elixir", "5.0.1", 3, starting: 1, age: 3 * 60},
    {"inventory", "gleam", "1.1.0", 1, age: 12 * 3600},
    {"reporting", "elixir", "3.2.0", 1, ghosted: {"3.3.0", :down}, age: 2 * 86_400},
    {"media_encoder", "erlang", "7.0.4", 2, atom_trend: true, age: 4 * 3600},
    {"chat", "elixir", "1.30.2", 3, tls_days: 5, age: 6 * 3600},
    {"pricing", "elixir", "2.0.0", 1, pre_commands: :failed, age: 60},
    {"recommendations", "elixir", "1.7.4", 2, ghosted: {"1.8.0", :up}, age: 20 * 3600},
    {"audit_log", "erlang", "2.2.0", 1, forced: 2, age: 7 * 86_400},
    {"webhooks", "elixir", "0.9.8", 2, age: 30 * 3600},
    {"scheduler", "gleam", "1.0.3", 1, age: 15 * 86_400},
    {"geo_lookup", "elixir", "3.4.1", 1, port: 91, age: 8 * 3600},
    {"ledger", "erlang", "6.1.0", 2, deploy: :hot_upgrade, age: 5 * 60},
    {"email_worker", "elixir", "1.12.0", 2, age: 2 * 86_400},
    {"feature_flags", "gleam", "0.4.2", 1, tls_days: 20, age: 40 * 86_400}
  ]

  def put_count(count), do: :persistent_term.put(__MODULE__, count)

  def find(name), do: Enum.find(apps(), &(&1.name == name))

  # The versions page of a fake app: its current version, and an earlier full deployment
  def history(name) do
    case find(name) do
      nil ->
        []

      app ->
        Enum.flat_map(app.children, fn child ->
          current = child.version || List.first(app.config.versions)
          at = DateTime.to_naive(child.deployed_at)

          [
            %Foundation.Catalog.Version{
              version: current,
              name: name,
              sname: child.sname,
              deployment: child.last_deployment,
              inserted_at: at
            },
            %Foundation.Catalog.Version{
              version: previous(current),
              name: name,
              sname: child.sname,
              deployment: :full_deployment,
              inserted_at: NaiveDateTime.add(at, -3 * 86_400, :second)
            }
          ]
        end)
    end
  end

  def ghosted(name) do
    case find(name) do
      %{config: %{last_ghosted_version: "-/-"}} ->
        []

      %{config: config, children: [child | _]} ->
        [
          %Foundation.Catalog.Version{
            version: config.last_ghosted_version,
            name: name,
            sname: child.sname,
            deployment: :full_deployment,
            inserted_at: DateTime.to_naive(config.last_ghosted_at)
          }
        ]

      _app ->
        []
    end
  end

  defp previous(version) do
    case version |> to_string() |> String.split(".") do
      [major, minor, patch] -> "#{major}.#{minor}.#{max(String.to_integer(patch) - 1, 0)}"
      _other -> "0.0.1"
    end
  end

  # More apps than the list repeat it with a number, like checkout_2
  def apps do
    now = DateTime.utc_now()
    count = :persistent_term.get(__MODULE__, length(@apps))

    @apps
    |> Stream.cycle()
    |> Stream.with_index()
    |> Enum.take(count)
    |> Enum.map(fn {{name, runtime, version, replicas, opts}, index} ->
      round = div(index, length(@apps))
      name = if round == 0, do: name, else: "#{name}_#{round + 1}"
      app({name, runtime, version, replicas, opts}, index, now)
    end)
  end

  defp app({name, runtime, version, replicas, opts}, index, now) do
    deployed_at = DateTime.add(now, -opts[:age], :second)

    {ghost, ghost_at} =
      case opts[:ghosted] do
        {ghost, _impact} -> {ghost, DateTime.add(now, -10 * 60, :second)}
        nil -> {"-/-", nil}
      end

    %Status{
      name: name,
      language: runtime,
      replicas: replicas,
      deploy_rollback_timeout_ms: 600_000,
      deploy_schedule_interval_ms: 5_000,
      monitoring: @monitoring,
      children:
        for(n <- 1..replicas, do: child(name, runtime, version, n, index, opts, deployed_at, now)),
      config: %{
        mode: if(opts[:pinned], do: :manual, else: :automatic),
        manual_version: opts[:pinned] && %{version: opts[:pinned]},
        versions: [version],
        last_ghosted_version: ghost,
        last_ghosted_at: ghost_at
      }
    }
  end

  defp child(name, runtime, version, n, index, opts, deployed_at, now) do
    sname =
      "#{name}-#{:erlang.phash2({index, n}, 2_000_000) |> Integer.to_string(36) |> String.downcase()}"

    status =
      cond do
        match?({_, :down}, opts[:ghosted]) -> :idle
        opts[:pre_commands] && n == 1 -> :pre_commands
        opts[:starting] && n <= opts[:starting] -> :starting
        true -> :running
      end

    %Status{
      name: name,
      sname: sname,
      node: :"#{sname}@fake-host",
      language: runtime,
      version: if(status == :idle, do: nil, else: version),
      status: status,
      failed_pre_commands:
        if(status == :pre_commands and opts[:pre_commands] == :failed,
          do: ["eval Pricing.Release.migrate()"],
          else: []
        ),
      last_deployment: opts[:deploy] || :full_deployment,
      deployed_at: deployed_at,
      uptime: uptime(opts[:age]),
      crash_restart_count: if(opts[:crash] && n == 1, do: 1, else: 0),
      force_restart_count: if(n == 1, do: opts[:forced] || 0, else: 0),
      last_crash_at: if(opts[:crash] && n == 1, do: DateTime.add(now, -opts[:crash], :second)),
      monitoring: @monitoring,
      ports: [%{key: "PORT", base: 4100 + index * 4 + n}],
      urls: ["https://#{String.replace(name, "_", "-")}.example.com"],
      otp_version: if(rem(index, 3) == 0, do: "28", else: "29"),
      elixir_version: "1.19.5",
      certificates: certificates(opts[:tls_days]),
      resources: if(status in [:running, :starting], do: resources(sname, index, n, opts))
    }
  end

  defp resources(sname, index, n, opts) do
    seed = :erlang.phash2({index, n})

    %Resources{
      sname: sname,
      cpu: rem(seed, 9) + 1,
      memory: (120 + rem(seed, 380)) * 1_048_576,
      process: limit(n == 1 && opts[:process], 900 + rem(seed, 600), 1_048_576),
      port: limit(n == 1 && opts[:port], 12 + rem(seed, 30), 65_536),
      atom:
        if(opts[:atom_trend] && n == 1,
          do: %Limit{
            count: 190_000,
            limit: 1_048_576,
            percent: 18,
            change_percent: 14,
            change_minutes: 60
          },
          else: limit(nil, 48_000 + rem(seed, 9_000), 1_048_576)
        )
    }
  end

  # A count near the limit, at the given percent, or a quiet one
  defp limit(percent, _count, max) when is_integer(percent),
    do: %Limit{
      count: div(max * percent, 100),
      limit: max,
      percent: percent,
      change_percent: 1,
      change_minutes: 60
    }

  defp limit(_percent, count, max),
    do: %Limit{
      count: count,
      limit: max,
      percent: trunc(count / max * 100),
      change_percent: 0,
      change_minutes: 60
    }

  defp certificates(nil), do: []

  defp certificates(days),
    do: [
      %Foundation.Certificates.PublicKey{
        issuer: "R11",
        expires_in_days: days,
        domains: ["example.com"]
      }
    ]

  defp uptime(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m ago"
  defp uptime(seconds) when seconds < 86_400, do: "#{div(seconds, 3600)}h ago"
  defp uptime(seconds), do: "#{div(seconds, 86_400)}d ago"
end

defmodule DevFakeApps.Status do
  @moduledoc false
  # Passes every call to the real adapter, adds the fakes to monitoring/0, and subscribes the pages to the
  # relay's topic, whose updates carry the fakes too
  @behaviour Deployer.Status.Adapter
  @real Deployer.Status.Application
  @topic "dev-fake-apps::monitoring_app_updated"

  # A fake app has no catalog on disk, so its history, ghosted list and changes are answered here
  @own [
    :monitoring,
    :subscribe,
    :history_version_list,
    :ghosted_version_list,
    :remove_ghosted_version,
    :clear_ghosted_versions,
    :set_mode
  ]

  for {fun, arity} <- Deployer.Status.Adapter.behaviour_info(:callbacks), fun not in @own do
    args = Macro.generate_arguments(arity, __MODULE__)
    @impl true
    def unquote(fun)(unquote_splicing(args)), do: apply(@real, unquote(fun), unquote(args))
  end

  defp fake?(name), do: DevFakeApps.Fakes.find(name) != nil

  @impl true
  def history_version_list(name, options) do
    if fake?(name),
      do: DevFakeApps.Fakes.history(name),
      else: @real.history_version_list(name, options)
  end

  @impl true
  def ghosted_version_list(name) do
    if fake?(name), do: DevFakeApps.Fakes.ghosted(name), else: @real.ghosted_version_list(name)
  end

  @impl true
  def remove_ghosted_version(name, version) do
    if fake?(name), do: {:ok, []}, else: @real.remove_ghosted_version(name, version)
  end

  @impl true
  def clear_ghosted_versions(name) do
    if fake?(name), do: {:ok, []}, else: @real.clear_ghosted_versions(name)
  end

  @impl true
  def set_mode(name, mode, version) do
    if fake?(name), do: {:ok, %{}}, else: @real.set_mode(name, mode, version)
  end

  @impl true
  def monitoring do
    {:ok, statuses} = @real.monitoring()
    {:ok, statuses ++ DevFakeApps.Fakes.apps()}
  end

  @impl true
  def subscribe, do: Phoenix.PubSub.subscribe(Deployer.PubSub, @topic)

  def topic, do: @topic
end

defmodule DevFakeApps.Relay do
  @moduledoc false
  # Passes each status update of this host on to the fake adapter's topic, with the fakes added
  use GenServer

  def start, do: GenServer.start(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    Deployer.Status.Application.subscribe()
    {:ok, nil}
  end

  @impl true
  def handle_info({:monitoring_app_updated, node, statuses}, state) do
    message = {:monitoring_app_updated, node, statuses ++ DevFakeApps.Fakes.apps()}
    Phoenix.PubSub.broadcast(Deployer.PubSub, DevFakeApps.Status.topic(), message)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end

DevFakeApps.Fakes.put_count(count)
if pid = Process.whereis(DevFakeApps.Relay), do: GenServer.stop(pid)
{:ok, _pid} = DevFakeApps.Relay.start()
Application.put_env(:deployer, Deployer.Status, adapter: DevFakeApps.Status)

"DeployEx shows #{count} fake apps. Reload the dashboard. make dev-fake-apps-off removes them."
