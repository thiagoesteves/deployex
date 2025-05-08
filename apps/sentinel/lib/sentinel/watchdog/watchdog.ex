defmodule Sentinel.Watchdog do
  @moduledoc """
  This server is responsible for receiving Host and Beam statistics and
  restart the system in case of a pre-defined threshold.
  """

  use GenServer
  require Logger

  alias Deployer.Monitor
  alias Foundation.Catalog
  alias Host.Memory
  alias ObserverWeb.Telemetry
  alias Sentinel.Watchdog.Data

  @watchdog_check_interval :timer.seconds(1)
  @monitored_app_limits [:port, :atom, :process]
  @monitored_app_metrics ["vm.port.total", "vm.atom.total", "vm.process.total", "vm.memory.total"]
  @watchdog_data :deployex_watchdog_data

  @type t :: %__MODULE__{
          enable_restart: boolean,
          warning_log_flag: boolean,
          warning_threshold_percent: nil | non_neg_integer(),
          restart_threshold_percent: nil | non_neg_integer()
        }

  defstruct enable_restart: true,
            warning_log_flag: false,
            warning_threshold_percent: 10,
            restart_threshold_percent: 20

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)

    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    Logger.info("Initializing Watchdog Server")

    # Subscribe to receive notifications if any node is UP or Down
    :net_kernel.monitor_nodes(true)

    :ets.new(@watchdog_data, [:set, :protected, :named_table])

    # List all expected nodes within the cluster
    monitored_nodes = Catalog.monitored_nodes()

    # Initialize Ets data
    reset_system_statistic()
    Enum.each(monitored_nodes, &reset_application_statistic/1)

    # Subscribe to receive System info
    Memory.subscribe()

    # Subscribe to receive Beam vm metrics from Observer Web
    Enum.each(monitored_nodes, fn node ->
      Enum.each(@monitored_app_metrics, &Telemetry.subscribe_for_new_data(node, &1))
    end)

    watchdog_check_interval =
      Keyword.get(args, :watchdog_check_interval, @watchdog_check_interval)

    schedule_new_check(watchdog_check_interval)

    {:ok,
     %{
       watchdog_check_interval: watchdog_check_interval,
       monitored_nodes: monitored_nodes,
       self_node: Node.self()
     }}
  end

  @impl true
  def handle_info(
        :watchdog_check,
        %{monitored_nodes: monitored_nodes, watchdog_check_interval: watchdog_check_interval} =
          state
      ) do
    check_monitored_app_limits = fn node ->
      Enum.each(@monitored_app_limits, fn type ->
        config = get_app_config(node, type)

        # credo:disable-for-lines:1
        case get_app_data(node, type) do
          %Data{current: count, limit: limit} when is_nil(count) or is_nil(limit) ->
            :ok

          %Data{current: count, limit: limit} ->
            current_percentage = trunc(count / limit * 100)
            threshold_check_monitored_apps_limits(node, type, current_percentage, config)
        end
      end)
    end

    check_system_memory_limits = fn ->
      # Check the application with highest usage in memory
      top_consumer_node = app_with_highest_usage(monitored_nodes)

      config = get_system_memory_config()

      case get_system_memory_data() do
        %Data{current: count, limit: limit} when is_nil(count) or is_nil(limit) ->
          :ok

        %Data{current: count, limit: limit} ->
          current_percentage = trunc(count / limit * 100)

          threshold_check_system_memory(top_consumer_node, current_percentage, config)
      end
    end

    # Check System Memory
    check_system_memory_limits.()

    # Check Applications limits
    Enum.each(monitored_nodes, &check_monitored_app_limits.(&1))

    # Schedule new check
    schedule_new_check(watchdog_check_interval)

    {:noreply, state}
  end

  def handle_info(
        {:update_system_info,
         %Memory{source_node: source_node, memory_free: memory_free, memory_total: memory_total}},
        %{self_node: self_node} = state
      ) do
    if source_node == self_node do
      :ets.insert(
        @watchdog_data,
        {{:system, :data, :memory},
         %Data{current: memory_total - memory_free, limit: memory_total}}
      )
    end

    {:noreply, state}
  end

  # NOTE: Ignore empty values, received during a restart
  def handle_info({:metrics_new_data, _source_node, _key, %Telemetry.Data{value: nil}}, state) do
    {:noreply, state}
  end

  def handle_info(
        {:metrics_new_data, source_node, "vm.port.total",
         %Telemetry.Data{measurements: %{total: count, limit: limit}}},
        %{monitored_nodes: monitored_nodes} = state
      ) do
    if source_node in monitored_nodes do
      :ets.insert(
        @watchdog_data,
        {{source_node, :data, :port}, %Data{current: count, limit: limit}}
      )
    end

    {:noreply, state}
  end

  def handle_info(
        {:metrics_new_data, source_node, "vm.atom.total",
         %Telemetry.Data{measurements: %{total: count, limit: limit}}},
        %{monitored_nodes: monitored_nodes} = state
      ) do
    if source_node in monitored_nodes do
      :ets.insert(
        @watchdog_data,
        {{source_node, :data, :atom}, %Data{current: count, limit: limit}}
      )
    end

    {:noreply, state}
  end

  def handle_info(
        {:metrics_new_data, source_node, "vm.process.total",
         %Telemetry.Data{measurements: %{total: count, limit: limit}}},
        %{monitored_nodes: monitored_nodes} = state
      ) do
    if source_node in monitored_nodes do
      :ets.insert(
        @watchdog_data,
        {{source_node, :data, :process}, %Data{current: count, limit: limit}}
      )
    end

    {:noreply, state}
  end

  def handle_info(
        {:metrics_new_data, source_node, "vm.memory.total",
         %Telemetry.Data{measurements: %{total: total_memory}}},
        %{monitored_nodes: monitored_nodes} = state
      ) do
    if source_node in monitored_nodes do
      :ets.insert(@watchdog_data, {{source_node, :data, :total_memory}, total_memory})
    end

    {:noreply, state}
  end

  def handle_info({:nodeup, _node}, state), do: {:noreply, state}

  def handle_info({:nodedown, node}, %{monitored_nodes: monitored_nodes} = state) do
    if node in monitored_nodes do
      reset_application_statistic(node)
    end

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  def get_app_data(node, type) do
    [{_, data}] = :ets.lookup(@watchdog_data, {node, :data, type})
    data
  end

  def get_app_config(node, type) do
    [{_, config}] = :ets.lookup(@watchdog_data, {node, :config, type})
    config
  end

  def get_system_memory_data do
    [{_, data}] = :ets.lookup(@watchdog_data, {:system, :data, :memory})
    data
  end

  def get_system_memory_config do
    [{_, config}] = :ets.lookup(@watchdog_data, {:system, :config, :memory})
    config
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

  defp schedule_new_check(interval), do: Process.send_after(self(), :watchdog_check, interval)

  defp load_system_config(type) do
    Application.fetch_env!(:sentinel, Sentinel.Watchdog)[:system_config][type]
  end

  defp load_node_config(node, type) do
    %{name_atom: name} = Catalog.parse_node_name(node)

    applications_config =
      Application.fetch_env!(:sentinel, Sentinel.Watchdog)[:applications_config]

    case applications_config[name] do
      nil ->
        applications_config[:default]

      app_monitoring_list ->
        Keyword.get(app_monitoring_list, type) || applications_config[:default]
    end
  end

  defp app_with_highest_usage(monitored_nodes) do
    {target_node, _memory} =
      Enum.reduce(monitored_nodes, {nil, 0}, fn node, {_node, memory} = acc ->
        [{_, value}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})

        if value != nil and value > memory do
          {node, value}
        else
          acc
        end
      end)

    target_node
  end

  defp reset_system_statistic do
    config = Map.merge(%__MODULE__{}, load_system_config(:memory))

    :ets.insert(@watchdog_data, {{:system, :config, :memory}, config})
    :ets.insert(@watchdog_data, {{:system, :data, :memory}, %Data{}})
  end

  defp reset_application_statistic(node) do
    Enum.each(@monitored_app_limits, fn statistic ->
      config = Map.merge(%__MODULE__{}, load_node_config(node, statistic))

      :ets.insert(@watchdog_data, {{node, :config, statistic}, config})
      :ets.insert(@watchdog_data, {{node, :data, statistic}, %Data{}})
    end)

    :ets.insert(@watchdog_data, {{node, :data, :total_memory}, nil})
  end

  defp threshold_check_monitored_apps_limits(
         node,
         type,
         current_percentage,
         %{
           enable_restart: true,
           restart_threshold_percent: restart_threshold_percent
         }
       )
       when current_percentage > restart_threshold_percent do
    Logger.error(
      "[#{node}] #{type} threshold exceeded: current #{current_percentage}% > restart #{restart_threshold_percent}%. Initiating restart..."
    )

    %{instance: instance} = Catalog.parse_node_name(node)
    Monitor.restart(instance)

    :ok
  end

  defp threshold_check_monitored_apps_limits(
         node,
         type,
         current_percentage,
         %{
           warning_log_flag: false,
           warning_threshold_percent: warning_threshold_percent
         } = config
       )
       when current_percentage > warning_threshold_percent do
    Logger.warning(
      "[#{node}] #{type} threshold exceeded: current #{current_percentage}% > warning #{warning_threshold_percent}%."
    )

    # Set flag indicating that warning log was emitted
    :ets.insert(@watchdog_data, {{node, :config, type}, %{config | warning_log_flag: true}})

    :ok
  end

  defp threshold_check_monitored_apps_limits(
         node,
         type,
         current_percentage,
         %{
           warning_log_flag: true,
           warning_threshold_percent: warning_threshold_percent
         } = config
       )
       when current_percentage <= warning_threshold_percent do
    Logger.warning(
      "[#{node}] #{type} threshold normalized: current #{current_percentage}% <= warning #{warning_threshold_percent}%."
    )

    # Reset warning log flag, current value was normalized
    :ets.insert(@watchdog_data, {{node, :config, type}, %{config | warning_log_flag: false}})

    :ok
  end

  defp threshold_check_monitored_apps_limits(_node, _type, _current_percentage, _config), do: :ok

  defp threshold_check_system_memory(nil, _current_percentage, _config), do: :ok

  defp threshold_check_system_memory(
         node,
         current_percentage,
         %{
           enable_restart: true,
           restart_threshold_percent: restart_threshold_percent
         }
       )
       when current_percentage > restart_threshold_percent do
    Logger.error(
      "Total Memory threshold exceeded: current #{current_percentage}% > restart #{restart_threshold_percent}%. Initiating restart for #{node} ..."
    )

    %{instance: instance} = Catalog.parse_node_name(node)
    Monitor.restart(instance)

    :ok
  end

  defp threshold_check_system_memory(
         _node,
         current_percentage,
         %{
           warning_log_flag: false,
           warning_threshold_percent: warning_threshold_percent
         } = config
       )
       when current_percentage > warning_threshold_percent do
    Logger.warning(
      "Total Memory threshold exceeded: current #{current_percentage}% > warning #{warning_threshold_percent}%."
    )

    # Set flag indicating that warning log was emitted
    :ets.insert(@watchdog_data, {{:system, :config, :memory}, %{config | warning_log_flag: true}})

    :ok
  end

  defp threshold_check_system_memory(
         _node,
         current_percentage,
         %{
           warning_log_flag: true,
           warning_threshold_percent: warning_threshold_percent
         } = config
       )
       when current_percentage <= warning_threshold_percent do
    Logger.warning(
      "Total Memory threshold normalized: current #{current_percentage}% <= warning #{warning_threshold_percent}%."
    )

    # Reset warning log flag, current value was normalized
    :ets.insert(
      @watchdog_data,
      {{:system, :config, :memory}, %{config | warning_log_flag: false}}
    )

    :ok
  end

  defp threshold_check_system_memory(_node, _current, _config), do: :ok
end
