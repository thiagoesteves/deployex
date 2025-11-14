defmodule Sentinel.Config.Watcher do
  @moduledoc """
  Monitors the Deployex YAML configuration file for changes to upgradable fields.

  Periodically checks the configuration file for changes by comparing checksums.
  When changes are detected in upgradable fields, generates a detailed diff of 
  modifications and holds them in a pending state until explicitly applied.

  ## Upgradable Fields

  Only a subset of configuration fields can be upgraded at runtime without restart:
  - deploy_rollback_timeout_ms
  - deploy_schedule_interval_ms
  - logs_retention_time_ms
  - metrics_retention_time_ms
  - monitoring settings
  - application configurations

  Fields like account_name, hostname, and cloud credentials are intentionally
  excluded as they require system-level restart.
  """

  use GenServer
  require Logger

  alias Deployer.Engine
  alias Deployer.Engine.Supervisor, as: EngineSupervisor
  alias Deployer.Monitor
  alias Deployer.Monitor.Supervisor, as: MonitorSupervisor
  alias Foundation.Catalog.Local
  alias Foundation.Yaml
  alias Sentinel.Config.Changes
  alias Sentinel.Config.Upgradable

  # 30 seconds
  @default_check_interval_ms 30_000

  @pubsub_topic_new "deployex::config::changes::new"
  @pubsub_topic_apply "deployex::config::changes::apply"

  defmodule State do
    @moduledoc false
    defstruct [
      :current_config,
      :pending_config,
      :pending_changes,
      :check_interval_ms
    ]

    @type t :: %__MODULE__{
            current_config: Upgradable.t(),
            pending_config: Upgradable.t() | nil,
            pending_changes: Changes.t() | nil,
            check_interval_ms: non_neg_integer()
          }
  end

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================

  @doc """
  Starts the configuration watcher GenServer.
  """
  def start_link(args \\ []) do
    name = Keyword.get(args, :name, __MODULE__)

    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    check_interval_ms = Keyword.get(args, :check_interval_ms, @default_check_interval_ms)

    # Load initial configuration from application environment
    current_config = Upgradable.from_app_env()

    Logger.info("Initializing ConfigWatcher for YAML configuration")

    state = %State{
      current_config: current_config,
      pending_config: nil,
      pending_changes: nil,
      check_interval_ms: check_interval_ms
    }

    schedule_check(state.check_interval_ms)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_pending_changes, _from, %State{pending_config: nil} = state) do
    {:reply, {:error, :no_pending_changes}, state}
  end

  def handle_call(:get_pending_changes, _from, %State{pending_config: _config} = state) do
    {:reply, {:ok, state.pending_changes}, state}
  end

  def handle_call(:apply_changes, _from, %State{pending_config: nil} = state) do
    {:reply, {:error, :no_pending_changes}, state}
  end

  def handle_call(:apply_changes, _from, state) do
    Logger.info("ConfigWatcher: Applying pending configuration changes")

    summary = state.pending_changes.summary

    apply_pre_config_changes(summary)

    # Build configuration updates from pending changes
    config_updates = build_config_updates(state.pending_changes.summary)

    # Apply all configuration updates at once
    Application.put_all_env(config_updates)

    apply_post_config_changes(summary)

    Logger.info("ConfigWatcher: Successfully applied configuration updates")

    # Notify subscribers about new changes
    Phoenix.PubSub.broadcast(
      Foundation.PubSub,
      @pubsub_topic_apply,
      {:watcher_config_apply, Node.self(), state.pending_changes}
    )

    new_state = %State{
      state
      | current_config: state.pending_config,
        pending_config: nil,
        pending_changes: nil
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:check_config, state) do
    new_state = check_for_changes(state)
    schedule_check(state.check_interval_ms)
    {:noreply, new_state}
  end

  ### ==========================================================================
  ### Public API
  ### ==========================================================================

  @doc """
  Gets pending configuration changes if any exist.

  Returns a map with detailed information about what changed between
  the current and pending configurations.
  """
  @spec get_pending_changes(GenServer.server()) ::
          {:ok, Changes.t()} | {:error, :no_pending_changes}
  def get_pending_changes(server \\ __MODULE__) do
    GenServer.call(server, :get_pending_changes)
  end

  @doc """
  Applies the pending configuration changes.
  """
  @spec apply_changes(GenServer.server()) :: :ok | {:error, :no_pending_changes}
  def apply_changes(server \\ __MODULE__) do
    GenServer.call(server, :apply_changes)
  end

  @doc """
  Subscribe to receive notification when new changes are available
  """
  @spec subscribe_new_config() :: :ok
  def subscribe_new_config do
    Phoenix.PubSub.subscribe(Foundation.PubSub, @pubsub_topic_new)
  end

  @doc """
  Subscribe to receive notification to apply new changes
  """
  @spec subscribe_apply_new_config() :: :ok
  def subscribe_apply_new_config do
    Phoenix.PubSub.subscribe(Foundation.PubSub, @pubsub_topic_apply)
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

  defp schedule_check(interval_ms) do
    Process.send_after(self(), :check_config, interval_ms)
  end

  defp check_for_changes(state) do
    case Yaml.load(%Yaml{config_checksum: state.current_config.config_checksum}) do
      {:ok, %Yaml{} = yaml_config} ->
        handle_yaml_change(state, yaml_config)

      {:error, reason} when reason in [:unchanged, :not_found] ->
        state

      {:error, reason} ->
        Logger.error("ConfigWatcher: Failed to load YAML configuration: #{inspect(reason)}")
        state
    end
  end

  defp handle_yaml_change(state, yaml_config) do
    # Extract upgradable fields from YAML
    yaml_upgradable = Upgradable.from_yaml(yaml_config)

    # Check for changes in upgradable fields
    case compute_changes(state.current_config, yaml_upgradable) do
      %{changes_count: 0} ->
        Logger.info("ConfigWatcher: No changes in upgradable fields")

        %{state | current_config: yaml_upgradable, pending_config: nil, pending_changes: nil}

      pending_changes ->
        # NOTE: Only Log and notify in the first event
        if is_nil(state.pending_config) or
             state.pending_config.config_checksum != yaml_upgradable.config_checksum do
          Logger.warning(
            "ConfigWatcher: Detected #{pending_changes.changes_count} change(s) in upgradable fields: #{inspect(Map.keys(pending_changes.summary))}"
          )

          Phoenix.PubSub.broadcast(
            Foundation.PubSub,
            @pubsub_topic_new,
            {:watcher_config_new, Node.self(), pending_changes}
          )
        end

        %{state | pending_config: yaml_upgradable, pending_changes: pending_changes}
    end
  end

  defp compute_changes(old_config, new_config) do
    summary = build_summary(old_config, new_config)

    %Changes{
      summary: summary,
      timestamp: DateTime.utc_now(),
      changes_count: summary |> Map.keys() |> length()
    }
  end

  defp build_summary(old, new) do
    %{}
    |> add_number_changes(:logs_retention_time_ms, old, new)
    |> add_number_changes(:metrics_retention_time_ms, old, new)
    |> add_monitoring_changes(old, new)
    |> add_application_changes(old, new)
  end

  defp add_number_changes(acc, field, old, new) do
    old_val = Map.get(old, field)
    new_val = Map.get(new, field)

    if new_val != nil and is_number(new_val) and old_val != new_val do
      Map.put(acc, field, %{old: old_val, new: new_val})
    else
      acc
    end
  end

  defp add_string_changes(acc, field, old, new) do
    old_val = Map.get(old, field)
    new_val = Map.get(new, field)

    if new_val != nil and is_binary(new_val) and old_val != new_val do
      Map.put(acc, field, %{old: old_val, new: new_val})
    else
      acc
    end
  end

  defp add_monitoring_changes(acc, old, new) do
    if diff_monitoring_list(old.monitoring, new.monitoring) != %{} do
      Map.put(acc, :monitoring, %{old: old.monitoring, new: new.monitoring})
    else
      acc
    end
  end

  defp diff_monitoring_list(old_list, new_list) do
    old_map = Map.new(old_list)
    new_map = Map.new(new_list)

    all_types = (Map.keys(old_map) ++ Map.keys(new_map)) |> Enum.uniq()

    Enum.reduce(all_types, %{}, fn type, acc ->
      old_mon = Map.get(old_map, type)
      new_mon = Map.get(new_map, type)

      cond do
        old_mon == nil ->
          Map.put(acc, type, %{status: :added, config: new_mon})

        new_mon == nil ->
          Map.put(acc, type, %{status: :removed, config: old_mon})

        Map.drop(old_mon, [:__struct__]) != Map.drop(new_mon, [:__struct__]) ->
          Map.put(acc, type, %{status: :modified, old: old_mon, new: new_mon})

        true ->
          acc
      end
    end)
  end

  defp add_env_changes(acc, old_app, new_app) do
    old_env = Enum.sort(old_app.env)
    new_env = Enum.sort(new_app.env)

    if old_env == new_env do
      acc
    else
      Map.put(acc, :env, %{old: old_env, new: new_env})
    end
  end

  defp add_replica_ports_changes(acc, old_app, new_app) do
    old_replica_ports = Enum.map(old_app.replica_ports, &"#{&1.key}=#{&1.base}") |> Enum.sort()
    new_replica_ports = Enum.map(new_app.replica_ports, &"#{&1.key}=#{&1.base}") |> Enum.sort()

    if old_replica_ports == new_replica_ports do
      acc
    else
      Map.put(acc, :replica_ports, %{old: old_app.replica_ports, new: new_app.replica_ports})
    end
  end

  defp add_application_changes(acc, old, new) do
    diff = diff_applications(old.applications, new.applications)

    if diff != %{} do
      Map.put(acc, :applications, %{old: old.applications, new: new.applications, details: diff})
    else
      acc
    end
  end

  defp diff_applications(old_apps, new_apps) do
    old_map = Map.new(old_apps, fn app -> {app.name, app} end)
    new_map = Map.new(new_apps, fn app -> {app.name, app} end)

    all_names = (Map.keys(old_map) ++ Map.keys(new_map)) |> Enum.uniq()

    Enum.reduce(all_names, %{}, fn name, acc ->
      old_app = Map.get(old_map, name)
      new_app = Map.get(new_map, name)

      cond do
        old_app == nil ->
          Map.put(acc, name, %{status: :added, config: new_app})

        new_app == nil ->
          Map.put(acc, name, %{status: :removed, config: old_app})

        Map.drop(old_app, [:__struct__]) != Map.drop(new_app, [:__struct__]) ->
          diff_application = diff_application(old_app, new_app)

          Map.put(acc, name, %{
            status: :modified,
            changes: diff_application
          })

        true ->
          acc
      end
    end)
  end

  defp diff_application(old_app, new_app) do
    %{}
    |> add_string_changes(:language, old_app, new_app)
    |> add_number_changes(:replicas, old_app, new_app)
    |> add_number_changes(:deploy_rollback_timeout_ms, old_app, new_app)
    |> add_number_changes(:deploy_schedule_interval_ms, old_app, new_app)
    |> add_replica_ports_changes(old_app, new_app)
    |> add_env_changes(old_app, new_app)
    |> add_monitoring_changes(old_app, new_app)
  end

  # credo:disable-for-lines:5
  defp apply_pre_config_changes(summary) do
    Enum.each(summary, fn {key, change} ->
      case key do
        :applications ->
          Enum.each(change.details, fn
            {name, %{status: :added}} ->
              Logger.info("ConfigWatcher: Setting up folders for the new application: #{name}")
              Local.setup_new_app(name)

            {name, %{status: :removed}} ->
              Logger.warning("ConfigWatcher: Removing application: #{name}")
              EngineSupervisor.stop_deployment(name)
              MonitorSupervisor.stop(name)

            _ ->
              nil
          end)

          :ok

        _ ->
          :ok
      end
    end)
  end

  # credo:disable-for-lines:15
  defp apply_post_config_changes(summary) do
    Enum.each(summary, fn {key, change} ->
      case key do
        :applications ->
          Enum.each(change.details, fn
            {name, %{status: :added}} ->
              application = Enum.find(change.new, &(&1.name == name))
              Logger.info("ConfigWatcher: Adding monitor deployment for application: #{name}")
              Monitor.init_monitor_supervisor(name)
              Engine.init_worker(application)
              :ok

            {name, %{status: :modified, changes: changes}} ->
              Enum.each(changes, fn {app_change_key, %{old: _old, new: new}} ->
                case app_change_key do
                  :monitoring ->
                    Sentinel.Watchdog.reset_app_statistics(name)
                    :ok

                  field ->
                    Engine.Worker.updated_state_values(name, Map.put(%{}, field, new))

                    :ok
                end
              end)

              :ok

            _ ->
              :ok
          end)

          :ok

        :monitoring ->
          Sentinel.Watchdog.reset_app_statistics("deployex")
          :ok

        :metrics_retention_time_ms ->
          ObserverWeb.Telemetry.update_data_retention_period(change.new)
          :ok

        :logs_retention_time_ms ->
          Sentinel.Logs.update_data_retention_period(change.new)
          :ok
      end
    end)
  end

  defp build_config_updates(summary) do
    Enum.reduce(summary, [], fn {key, change}, acc ->
      case key do
        :metrics_retention_time_ms ->
          add_observer_web_config(acc, change.new)

        _ ->
          add_foundation_config(acc, key, change.new)
      end
    end)
  end

  defp add_foundation_config(config_list, key, value) do
    foundation_config = Keyword.get(config_list, :foundation, [])
    updated_foundation = Keyword.put(foundation_config, key, value)
    Keyword.put(config_list, :foundation, updated_foundation)
  end

  defp add_observer_web_config(config_list, retention_time_ms) do
    Keyword.put(config_list, :observer_web, data_retention_period: retention_time_ms)
  end
end
