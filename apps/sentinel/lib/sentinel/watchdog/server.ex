defmodule Sentinel.Watchdog.Server do
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
    # List all expected nodes within the cluster, excluding deployex
    self_node = Node.self()
    expected_nodes = Catalog.expected_nodes() -- [self_node]

    # TODO: Capture configuration from YAML file
    :ets.insert(@watchdog_data, {{:system_info, :config}, %Sentinel.Watchdog.Data{}})
    :ets.insert(@watchdog_data, {{:system_info, :data}, %Memory{}})

    Enum.each(expected_nodes, &reset_application_statistic/1)

    # Subscribe to receive System info
    Memory.subscribe()

    # Subscribe to receive Beam VM statistics
    BeamVm.Server.subscribe()

    args
    |> Keyword.get(:watchdog_check_interval, @watchdog_check_interval)
    |> :timer.send_interval(:watchdog_check)

    {:ok,
     %{
       expected_nodes: expected_nodes,
       self_node: self_node
     }}
  end

  @impl true
  def handle_info(:watchdog_check, %{expected_nodes: expected_nodes} = state) do
    check_monitored_app_limits = fn node ->
      Enum.each(@monitored_app_limits, fn type ->
        [{_, config}] = :ets.lookup(@watchdog_data, {node, :config, type})

        case :ets.lookup(@watchdog_data, {node, :data, type}) do
          [{_, %{count: count, limit: limit}}] when is_nil(count) or is_nil(limit) ->
            :ok

          [{_, %{count: count, limit: limit}}] ->
            current = trunc(count / limit * 100)
            threshold_check_monitored_apps_limits(node, type, current, config)
        end
      end)
    end

    check_system_memory_limits = fn ->
      # Check the application with highest usage in memory
      top_consumer_node = app_with_highest_usage(expected_nodes)

      [{_, config}] = :ets.lookup(@watchdog_data, {:system_info, :config})

      case :ets.lookup(@watchdog_data, {:system_info, :data}) do
        [{_, %{memory_free: memory_free, memory_total: memory_total}}]
        when is_nil(memory_free) or is_nil(memory_total) ->
          :ok

        [{_, %{memory_free: memory_free, memory_total: memory_total}}] ->
          current = trunc((memory_total - memory_free) / memory_total * 100)

          threshold_check_system_memory(top_consumer_node, current, config)
      end
    end

    # Check System Memory
    check_system_memory_limits.()

    # Check Applications limits
    Enum.each(expected_nodes, &check_monitored_app_limits.(&1))

    {:noreply, state}
  end

  def handle_info(
        {:update_system_info, %Memory{source_node: source_node} = system_info},
        %{self_node: self_node} = state
      ) do
    if source_node == self_node do
      :ets.insert(@watchdog_data, {{:system_info, :data}, system_info})
    end

    {:noreply, state}
  end

  def handle_info(
        {:beam_vm_update_statistics, %BeamVm{source_node: source_node, statistics: statistics}},
        %{self_node: self_node, expected_nodes: expected_nodes} = state
      ) do
    if source_node == self_node do
      Enum.each(expected_nodes, fn node ->
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
              {{node, :data, :port}, %{count: port_count, limit: port_limit}}
            )

            :ets.insert(
              @watchdog_data,
              {{node, :data, :atom}, %{count: atom_count, limit: atom_limit}}
            )

            :ets.insert(
              @watchdog_data,
              {{node, :data, :process}, %{count: process_count, limit: process_limit}}
            )

            :ets.insert(@watchdog_data, {{node, :data, :total_memory}, total_memory})
        end
      end)
    end

    {:noreply, state}
  end

  def handle_info({:nodeup, _node}, state), do: {:noreply, state}

  def handle_info({:nodedown, node}, %{expected_nodes: expected_nodes} = state) do
    if node in expected_nodes do
      reset_application_statistic(node)
    end

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

  defp app_with_highest_usage(expected_nodes) do
    {target_node, _memory} =
      Enum.reduce(expected_nodes, {nil, 0}, fn node, {_node, memory} = acc ->
        [{_, value}] = :ets.lookup(@watchdog_data, {node, :data, :total_memory})

        if value != nil and value > memory do
          {node, value}
        else
          acc
        end
      end)

    target_node
  end

  defp reset_application_statistic(node) do
    Enum.each(@monitored_app_limits, fn statistic ->
      :ets.insert(@watchdog_data, {{node, :config, statistic}, %Sentinel.Watchdog.Data{}})
      :ets.insert(@watchdog_data, {{node, :data, statistic}, %{count: nil, limit: nil}})
    end)

    :ets.insert(@watchdog_data, {{node, :data, :total_memory}, nil})
  end

  defp threshold_check_monitored_apps_limits(
         node,
         type,
         current,
         %{
           restart_enabled: true,
           restart_threshold: restart_threshold
         }
       )
       when current > restart_threshold do
    Logger.error(
      "[#{node}] #{type} threshold exceeded: current #{current}% > restart #{restart_threshold}%. Initiating restart..."
    )

    node
    |> Catalog.node_to_instance()
    |> Monitor.restart()

    :ok
  end

  defp threshold_check_monitored_apps_limits(
         node,
         type,
         current,
         %{
           warning_log: false,
           warning_threshold: warning_threshold
         } = config
       )
       when current > warning_threshold do
    Logger.warning(
      "[#{node}] #{type} threshold exceeded: current #{current}% > warning #{warning_threshold}%."
    )

    # Set flag indicating that warning log was emitted
    :ets.insert(@watchdog_data, {{node, :config, type}, %{config | warning_log: true}})

    :ok
  end

  defp threshold_check_monitored_apps_limits(
         node,
         type,
         current,
         %{
           warning_log: true,
           warning_threshold: warning_threshold
         } = config
       )
       when current <= warning_threshold do
    Logger.warning(
      "[#{node}] #{type} threshold normalized: current #{current}% <= warning #{warning_threshold}%."
    )

    # Reset warning log flag, current value was normalized
    :ets.insert(@watchdog_data, {{node, :config, type}, %{config | warning_log: false}})

    :ok
  end

  defp threshold_check_monitored_apps_limits(_node, _type, _current, _config), do: :ok

  defp threshold_check_system_memory(nil, _current, _config), do: :ok

  defp threshold_check_system_memory(
         node,
         current,
         %{
           restart_enabled: true,
           restart_threshold: restart_threshold
         }
       )
       when current > restart_threshold do
    Logger.error(
      "Total Memory threshold exceeded: current #{current}% > restart #{restart_threshold}%. Initiating restart for #{node} ..."
    )

    node
    |> Catalog.node_to_instance()
    |> Monitor.restart()

    :ok
  end

  defp threshold_check_system_memory(
         _node,
         current,
         %{
           warning_log: false,
           warning_threshold: warning_threshold
         } = config
       )
       when current > warning_threshold do
    Logger.warning(
      "Total Memory threshold exceeded: current #{current}% > warning #{warning_threshold}%."
    )

    # Set flag indicating that warning log was emitted
    :ets.insert(@watchdog_data, {{:system_info, :config}, %{config | warning_log: true}})

    :ok
  end

  defp threshold_check_system_memory(
         _node,
         current,
         %{
           warning_log: true,
           warning_threshold: warning_threshold
         } = config
       )
       when current <= warning_threshold do
    Logger.warning(
      "Total Memory threshold normalized: current #{current}% <= warning #{warning_threshold}%."
    )

    # Reset warning log flag, current value was normalized
    :ets.insert(@watchdog_data, {{:system_info, :config}, %{config | warning_log: false}})

    :ok
  end

  defp threshold_check_system_memory(_node, _current, _config), do: :ok
end
