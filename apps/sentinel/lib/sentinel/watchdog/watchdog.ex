defmodule Sentinel.Watchdog do
  @moduledoc """
  This server is responsible for receiving Host and Beam statistics and
  restart the system in case of a pre-defined threshold.
  """

  use GenServer
  require Logger

  alias Deployer.Deployex
  alias Deployer.Monitor
  alias Foundation.Catalog
  alias Host.Info
  alias ObserverWeb.Telemetry
  alias Sentinel.Watchdog.Data

  @watchdog_check_interval :timer.seconds(1)
  @monitored_app_limits [:port, :atom, :process]
  @monitored_app_metrics ["vm.port.total", "vm.atom.total", "vm.process.total", "vm.memory.total"]
  # DeployEx watches the same Beam VM limits as any monitored application. Its memory is handled
  # apart, it tracks the host memory reported by Host.Info instead of the VM allocated memory
  @deployex_limits [:port, :atom, :process]
  @deployex_metrics ["vm.port.total", "vm.atom.total", "vm.process.total"]
  # The termination is the only explanation an operator gets for DeployEx disappearing, so the
  # delay has to outlive the round trip of the notification announcing it, not only its dispatch
  @deployex_terminate_delay :timer.seconds(3)
  @watchdog_data :deployex_watchdog_data

  @type t :: %__MODULE__{
          enabled: boolean(),
          enable_restart: boolean(),
          warning_log_flag: boolean(),
          warning_threshold_percent: nil | non_neg_integer(),
          restart_threshold_percent: nil | non_neg_integer()
        }

  defstruct enabled: true,
            enable_restart: true,
            warning_log_flag: false,
            warning_threshold_percent: 75,
            restart_threshold_percent: 90

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

    # Subscribe to receive a notification every time we have a new deploy
    Monitor.subscribe_new_deploy()

    :ets.new(@watchdog_data, [:set, :protected, :named_table])

    sname_to_node = fn sname ->
      %{node: node} = Catalog.node_info(sname)
      node
    end

    # List nodes that are being monitored by deployex
    monitored_nodes = Enum.map(Monitor.list(), &sname_to_node.(&1))

    # Initialize Ets data
    reset_deployex_statistic()
    Enum.each(monitored_nodes, &reset_application_statistic/1)

    # Subscribe to receive System info
    Info.subscribe()

    # Subscribe to receive Beam vm metrics from Observer Web
    Enum.each(monitored_nodes, fn node ->
      Enum.each(@monitored_app_metrics, &Telemetry.subscribe_for_new_data(node, &1))
    end)

    # Subscribe to receive DeployEx own Beam vm metrics from Observer Web
    Enum.each(@deployex_metrics, &Telemetry.subscribe_for_new_data(Node.self(), &1))

    watchdog_check_interval =
      Keyword.get(args, :watchdog_check_interval, @watchdog_check_interval)

    schedule_new_check(watchdog_check_interval)

    {:ok,
     %{
       watchdog_check_interval: watchdog_check_interval,
       deployex_terminate_delay:
         Keyword.get(args, :deployex_terminate_delay, @deployex_terminate_delay),
       monitored_nodes: monitored_nodes,
       self_node: Node.self()
     }}
  end

  @impl true
  def handle_call({:reset_app_statistics, "deployex"}, _from, state) do
    reset_deployex_statistic()
    {:reply, :ok, state}
  end

  def handle_call({:reset_app_statistics, app_name}, _from, state) do
    state.monitored_nodes
    |> Enum.each(fn node ->
      case Catalog.node_info(node) do
        %{name: ^app_name} ->
          reset_application_statistic(node)

        _ ->
          nil
      end
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_info(
        :watchdog_check,
        %{
          monitored_nodes: monitored_nodes,
          watchdog_check_interval: watchdog_check_interval,
          deployex_terminate_delay: deployex_terminate_delay
        } = state
      ) do
    check_monitored_app_limits = fn node ->
      Enum.each(@monitored_app_limits, fn type ->
        config = get_app_config(node, type)

        with_percentage(config, get_app_data(node, type), fn current_percentage ->
          threshold_check_monitored_apps_limits(node, type, current_percentage, config)
        end)
      end)
    end

    check_deployex_memory_limits = fn ->
      # Check the application with highest usage in memory
      top_consumer_node = app_with_highest_usage(monitored_nodes)

      config = get_deployex_config(:memory)

      with_percentage(config, get_deployex_data(:memory), fn current_percentage ->
        threshold_check_deployex_memory(top_consumer_node, current_percentage, config)
      end)
    end

    # A restart tears down the whole node, so the first resource asking for one ends the sweep
    check_deployex_limits = fn ->
      Enum.find(@deployex_limits, fn type ->
        config = get_deployex_config(type)

        :restarting ==
          with_percentage(config, get_deployex_data(type), fn current_percentage ->
            threshold_check_deployex_limits(
              type,
              current_percentage,
              config,
              deployex_terminate_delay
            )
          end)
      end)
    end

    # Check System Memory
    check_deployex_memory_limits.()

    # Check DeployEx Beam VM limits
    check_deployex_limits.()

    # Check Applications limits
    Enum.each(monitored_nodes, &check_monitored_app_limits.(&1))

    # Schedule new check
    schedule_new_check(watchdog_check_interval)

    {:noreply, state}
  end

  def handle_info(
        {:update_system_info,
         %Info{source_node: source_node, memory_free: memory_free, memory_total: memory_total}},
        %{self_node: self_node} = state
      ) do
    if source_node == self_node do
      :ets.insert(
        @watchdog_data,
        {{:deployex, :data, :memory},
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
        state
      ) do
    store_vm_limit(source_node, :port, %Data{current: count, limit: limit}, state)

    {:noreply, state}
  end

  def handle_info(
        {:metrics_new_data, source_node, "vm.atom.total",
         %Telemetry.Data{measurements: %{total: count, limit: limit}}},
        state
      ) do
    store_vm_limit(source_node, :atom, %Data{current: count, limit: limit}, state)

    {:noreply, state}
  end

  def handle_info(
        {:metrics_new_data, source_node, "vm.process.total",
         %Telemetry.Data{measurements: %{total: count, limit: limit}}},
        state
      ) do
    store_vm_limit(source_node, :process, %Data{current: count, limit: limit}, state)

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

  def handle_info(
        {:new_deploy, source_node, sname},
        %{monitored_nodes: monitored_nodes} = state
      ) do
    %{node: node} = Catalog.node_info(sname)

    with true <- source_node == Node.self(),
         false <- node in monitored_nodes do
      # Prepare node for monitoring
      reset_application_statistic(node)

      Enum.each(
        @monitored_app_metrics,
        &Telemetry.subscribe_for_new_data(Atom.to_string(node), &1)
      )

      {:noreply, %{state | monitored_nodes: monitored_nodes ++ [node]}}
    else
      _error ->
        {:noreply, state}
    end
  end

  def handle_info({:nodeup, _node}, state), do: {:noreply, state}

  def handle_info({:nodedown, node}, %{monitored_nodes: monitored_nodes} = state) do
    if node in monitored_nodes do
      reset_application_statistic(node)
      {:noreply, %{state | monitored_nodes: monitored_nodes -- [node]}}
    else
      {:noreply, state}
    end
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec get_app_data(node :: node(), type :: atom()) :: Data.t()
  def get_app_data(node, type) do
    [{_, data}] = :ets.lookup(@watchdog_data, {node, :data, type})
    data
  end

  @spec get_app_config(node :: node(), type :: atom()) :: map()
  def get_app_config(node, type) do
    [{_, config}] = :ets.lookup(@watchdog_data, {node, :config, type})
    config
  end

  @spec get_deployex_data(type :: atom()) :: Data.t()
  def get_deployex_data(type) do
    [{_, data}] = :ets.lookup(@watchdog_data, {:deployex, :data, type})
    data
  end

  @spec get_deployex_config(type :: atom()) :: map()
  def get_deployex_config(type) do
    [{_, config}] = :ets.lookup(@watchdog_data, {:deployex, :config, type})
    config
  end

  @spec reset_app_statistics(name :: String.t()) :: :ok
  def reset_app_statistics(name) do
    GenServer.call(__MODULE__, {:reset_app_statistics, name})
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

  defp schedule_new_check(interval), do: Process.send_after(self(), :watchdog_check, interval)

  defp load_deployex_config(type) do
    case Application.fetch_env!(:foundation, :monitoring)[type] do
      nil ->
        %__MODULE__{enabled: false}

      deployex_monitoring ->
        Map.merge(%__MODULE__{}, deployex_monitoring)
    end
  end

  defp load_node_config(node, type) do
    with %{name: name} <- Catalog.node_info(node),
         %{monitoring: monitoring} <- Enum.find(Catalog.applications(), &(&1.name == name)),
         %{} = mon_type <- monitoring[type] do
      Map.merge(%__MODULE__{}, mon_type)
    else
      _ -> %__MODULE__{enabled: false}
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

  # A resource is only evaluated when it is configured and both ends of the ratio are known,
  # the data starts empty and stays empty until the first metric for that resource arrives
  defp with_percentage(%{enabled: false}, _data, _fun), do: :ok

  defp with_percentage(_config, %Data{current: count, limit: limit}, _fun)
       when is_nil(count) or is_nil(limit),
       do: :ok

  defp with_percentage(_config, %Data{current: count, limit: limit}, fun) do
    fun.(trunc(count / limit * 100))
  end

  defp store_vm_limit(source_node, type, %Data{} = data, %{
         self_node: self_node,
         monitored_nodes: monitored_nodes
       }) do
    cond do
      source_node == self_node ->
        :ets.insert(@watchdog_data, {{:deployex, :data, type}, data})

      source_node in monitored_nodes ->
        :ets.insert(@watchdog_data, {{source_node, :data, type}, data})

      true ->
        :ok
    end
  end

  defp reset_deployex_statistic do
    Enum.each([:memory | @deployex_limits], fn type ->
      config = load_deployex_config(type)

      :ets.insert(@watchdog_data, {{:deployex, :config, type}, config})
      :ets.insert(@watchdog_data, {{:deployex, :data, type}, %Data{}})
    end)

    :ok
  end

  defp reset_application_statistic(node) do
    Enum.each(@monitored_app_limits, fn statistic ->
      config = load_node_config(node, statistic)

      :ets.insert(@watchdog_data, {{node, :config, statistic}, config})
      :ets.insert(@watchdog_data, {{node, :data, statistic}, %Data{}})
    end)

    :ets.insert(@watchdog_data, {{node, :data, :total_memory}, nil})

    :ok
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

    %{sname: sname} = Catalog.node_info(node)
    Monitor.restart(sname)

    Foundation.Notifications.notify("watchdog_threshold_exceeded", %{
      node: node,
      type: type,
      current_percentage: current_percentage,
      restart_threshold_percent: restart_threshold_percent
    })

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

    Foundation.Notifications.notify("watchdog_threshold_warning", %{
      node: node,
      type: type,
      current_percentage: current_percentage,
      warning_threshold_percent: warning_threshold_percent,
      action: :warning
    })

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

    Foundation.Notifications.notify("watchdog_threshold_warning", %{
      node: node,
      type: type,
      current_percentage: current_percentage,
      warning_threshold_percent: warning_threshold_percent,
      action: :normalized
    })

    # Reset warning log flag, current value was normalized
    :ets.insert(@watchdog_data, {{node, :config, type}, %{config | warning_log_flag: false}})

    :ok
  end

  defp threshold_check_monitored_apps_limits(_node, _type, _current_percentage, _config), do: :ok

  defp threshold_check_deployex_memory(nil, _current_percentage, _config), do: :ok

  defp threshold_check_deployex_memory(
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

    %{sname: sname} = Catalog.node_info(node)
    Monitor.restart(sname)

    Foundation.Notifications.notify("watchdog_threshold_exceeded", %{
      node: node,
      type: :memory,
      current_percentage: current_percentage,
      restart_threshold_percent: restart_threshold_percent
    })

    :ok
  end

  defp threshold_check_deployex_memory(
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

    Foundation.Notifications.notify("watchdog_threshold_warning", %{
      node: node(),
      type: :memory,
      current_percentage: current_percentage,
      warning_threshold_percent: warning_threshold_percent,
      action: :warning
    })

    # Set flag indicating that warning log was emitted
    :ets.insert(
      @watchdog_data,
      {{:deployex, :config, :memory}, %{config | warning_log_flag: true}}
    )

    :ok
  end

  defp threshold_check_deployex_memory(
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

    Foundation.Notifications.notify("watchdog_threshold_warning", %{
      node: node(),
      type: :memory,
      current_percentage: current_percentage,
      warning_threshold_percent: warning_threshold_percent,
      action: :normalized
    })

    # Reset warning log flag, current value was normalized
    :ets.insert(
      @watchdog_data,
      {{:deployex, :config, :memory}, %{config | warning_log_flag: false}}
    )

    :ok
  end

  defp threshold_check_deployex_memory(_node, _current, _config), do: :ok

  # DeployEx exhausting its own Beam VM limits can only be cleared by restarting DeployEx itself,
  # restarting a monitored application would not release the atoms, processes or ports leaked here.
  # When installed as a systemd service the termination is followed by an automatic restart
  defp threshold_check_deployex_limits(
         type,
         current_percentage,
         %{
           enable_restart: true,
           restart_threshold_percent: restart_threshold_percent
         },
         terminate_delay
       )
       when current_percentage > restart_threshold_percent do
    Logger.error(
      "[deployex] #{type} threshold exceeded: current #{current_percentage}% > restart #{restart_threshold_percent}%. Initiating restart..."
    )

    Foundation.Notifications.notify("watchdog_threshold_exceeded", %{
      node: Node.self(),
      type: type,
      current_percentage: current_percentage,
      restart_threshold_percent: restart_threshold_percent
    })

    Deployex.force_terminate(terminate_delay)

    :restarting
  end

  defp threshold_check_deployex_limits(
         type,
         current_percentage,
         %{
           warning_log_flag: false,
           warning_threshold_percent: warning_threshold_percent
         } = config,
         _terminate_delay
       )
       when current_percentage > warning_threshold_percent do
    Logger.warning(
      "[deployex] #{type} threshold exceeded: current #{current_percentage}% > warning #{warning_threshold_percent}%."
    )

    Foundation.Notifications.notify("watchdog_threshold_warning", %{
      node: Node.self(),
      type: type,
      current_percentage: current_percentage,
      warning_threshold_percent: warning_threshold_percent,
      action: :warning
    })

    # Set flag indicating that warning log was emitted
    :ets.insert(@watchdog_data, {{:deployex, :config, type}, %{config | warning_log_flag: true}})

    :ok
  end

  defp threshold_check_deployex_limits(
         type,
         current_percentage,
         %{
           warning_log_flag: true,
           warning_threshold_percent: warning_threshold_percent
         } = config,
         _terminate_delay
       )
       when current_percentage <= warning_threshold_percent do
    Logger.warning(
      "[deployex] #{type} threshold normalized: current #{current_percentage}% <= warning #{warning_threshold_percent}%."
    )

    Foundation.Notifications.notify("watchdog_threshold_warning", %{
      node: Node.self(),
      type: type,
      current_percentage: current_percentage,
      warning_threshold_percent: warning_threshold_percent,
      action: :normalized
    })

    # Reset warning log flag, current value was normalized
    :ets.insert(@watchdog_data, {{:deployex, :config, type}, %{config | warning_log_flag: false}})

    :ok
  end

  defp threshold_check_deployex_limits(_type, _current_percentage, _config, _terminate_delay),
    do: :ok
end
