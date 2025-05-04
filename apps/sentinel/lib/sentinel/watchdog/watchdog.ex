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
  alias Sentinel.Monitoring.BeamVm
  alias Sentinel.Watchdog.Config
  alias Sentinel.Watchdog.Data

  @watchdog_check_interval :timer.seconds(1)
  @monitored_app_limits [:port, :atom, :process]
  @watchdog_data :deployex_watchdog_data

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

    # Subscribe to receive Beam VM statistics
    BeamVm.Server.subscribe()

    args
    |> Keyword.get(:watchdog_check_interval, @watchdog_check_interval)
    |> :timer.send_interval(:watchdog_check)

    {:ok,
     %{
       monitored_nodes: monitored_nodes,
       self_node: Node.self()
     }}
  end

  @impl true
  def handle_info(:watchdog_check, %{monitored_nodes: monitored_nodes} = state) do
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

      config = get_memory_config()

      case get_memory_data() do
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

  def handle_info(
        {:beam_vm_update_statistics, %BeamVm{source_node: source_node, statistics: statistics}},
        %{self_node: self_node, monitored_nodes: monitored_nodes} = state
      ) do
    # credo:disable-for-lines:3
    if source_node == self_node do
      Enum.each(monitored_nodes, fn node ->
        case Map.get(statistics, node) do
          nil ->
            :ok

          %{
            total_memory: total_memory,
            port_limit: port_limit,
            port_count: port_count,
            atom_count: atom_count,
            atom_limit: atom_limit,
            process_limit: process_limit,
            process_count: process_count
          } ->
            :ets.insert(
              @watchdog_data,
              {{node, :data, :port}, %Data{current: port_count, limit: port_limit}}
            )

            :ets.insert(
              @watchdog_data,
              {{node, :data, :atom}, %Data{current: atom_count, limit: atom_limit}}
            )

            :ets.insert(
              @watchdog_data,
              {{node, :data, :process}, %Data{current: process_count, limit: process_limit}}
            )

            :ets.insert(@watchdog_data, {{node, :data, :total_memory}, total_memory})
        end
      end)
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

  def get_memory_data do
    [{_, data}] = :ets.lookup(@watchdog_data, {:system, :data, :memory})
    data
  end

  def get_memory_config do
    [{_, config}] = :ets.lookup(@watchdog_data, {:system, :config, :memory})
    config
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

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

      app ->
        Map.get(app, type) || applications_config[:default]
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
    config = Map.merge(%Config{}, load_system_config(:memory))

    :ets.insert(@watchdog_data, {{:system, :config, :memory}, config})
    :ets.insert(@watchdog_data, {{:system, :data, :memory}, %Data{}})
  end

  defp reset_application_statistic(node) do
    Enum.each(@monitored_app_limits, fn statistic ->
      config = Map.merge(%Config{}, load_node_config(node, statistic))

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
           restart_enabled: true,
           restart_threshold: restart_threshold
         }
       )
       when current_percentage > restart_threshold do
    Logger.error(
      "[#{node}] #{type} threshold exceeded: current #{current_percentage}% > restart #{restart_threshold}%. Initiating restart..."
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
           warning_log: false,
           warning_threshold: warning_threshold
         } = config
       )
       when current_percentage > warning_threshold do
    Logger.warning(
      "[#{node}] #{type} threshold exceeded: current #{current_percentage}% > warning #{warning_threshold}%."
    )

    # Set flag indicating that warning log was emitted
    :ets.insert(@watchdog_data, {{node, :config, type}, %{config | warning_log: true}})

    :ok
  end

  defp threshold_check_monitored_apps_limits(
         node,
         type,
         current_percentage,
         %{
           warning_log: true,
           warning_threshold: warning_threshold
         } = config
       )
       when current_percentage <= warning_threshold do
    Logger.warning(
      "[#{node}] #{type} threshold normalized: current #{current_percentage}% <= warning #{warning_threshold}%."
    )

    # Reset warning log flag, current value was normalized
    :ets.insert(@watchdog_data, {{node, :config, type}, %{config | warning_log: false}})

    :ok
  end

  defp threshold_check_monitored_apps_limits(_node, _type, _current_percentage, _config), do: :ok

  defp threshold_check_system_memory(nil, _current_percentage, _config), do: :ok

  defp threshold_check_system_memory(
         node,
         current_percentage,
         %{
           restart_enabled: true,
           restart_threshold: restart_threshold
         }
       )
       when current_percentage > restart_threshold do
    Logger.error(
      "Total Memory threshold exceeded: current #{current_percentage}% > restart #{restart_threshold}%. Initiating restart for #{node} ..."
    )

    %{instance: instance} = Catalog.parse_node_name(node)
    Monitor.restart(instance)

    :ok
  end

  defp threshold_check_system_memory(
         _node,
         current_percentage,
         %{
           warning_log: false,
           warning_threshold: warning_threshold
         } = config
       )
       when current_percentage > warning_threshold do
    Logger.warning(
      "Total Memory threshold exceeded: current #{current_percentage}% > warning #{warning_threshold}%."
    )

    # Set flag indicating that warning log was emitted
    :ets.insert(@watchdog_data, {{:system, :config, :memory}, %{config | warning_log: true}})

    :ok
  end

  defp threshold_check_system_memory(
         _node,
         current_percentage,
         %{
           warning_log: true,
           warning_threshold: warning_threshold
         } = config
       )
       when current_percentage <= warning_threshold do
    Logger.warning(
      "Total Memory threshold normalized: current #{current_percentage}% <= warning #{warning_threshold}%."
    )

    # Reset warning log flag, current value was normalized
    :ets.insert(@watchdog_data, {{:system, :config, :memory}, %{config | warning_log: false}})

    :ok
  end

  defp threshold_check_system_memory(_node, _current, _config), do: :ok
end
