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

  @type level :: :ok | :warning | :critical

  @type t :: %__MODULE__{
          enabled: boolean(),
          enable_restart: boolean(),
          level: level(),
          warning_threshold_percent: nil | non_neg_integer(),
          restart_threshold_percent: nil | non_neg_integer()
        }

  defstruct enabled: true,
            enable_restart: true,
            level: :ok,
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

        resource = %{
          owner: node,
          type: type,
          label: "[#{node}] #{type}",
          node: node,
          repeat_restart: true,
          restart: fn -> restart_application(node) end
        }

        with_percentage(config, get_app_data(node, type), &check_level(resource, config, &1))
      end)
    end

    check_deployex_memory_limits = fn ->
      # Check the application with highest usage in memory
      top_consumer_node = app_with_highest_usage(monitored_nodes)

      config = get_deployex_config(:memory)

      resource = %{
        owner: :deployex,
        type: :memory,
        label: "Total Memory",
        node: Node.self(),
        repeat_restart: true,
        restart: fn -> restart_top_memory_consumer(top_consumer_node) end
      }

      with_percentage(config, get_deployex_data(:memory), &check_level(resource, config, &1))
    end

    # A restart tears down the whole node, so the first resource asking for one ends the sweep
    check_deployex_limits = fn ->
      Enum.find(@deployex_limits, fn type ->
        config = get_deployex_config(type)

        resource = %{
          owner: :deployex,
          type: type,
          label: "[deployex] #{type}",
          node: Node.self(),
          repeat_restart: false,
          restart: fn -> terminate_deployex(deployex_terminate_delay) end
        }

        :restarting ==
          with_percentage(config, get_deployex_data(type), &check_level(resource, config, &1))
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

  # Every resource is watched through the level its usage falls into. Reporting follows the
  # changes of level, a resource sitting above a threshold repeats neither its log line nor its
  # notification, and a resource that crosses both thresholds at once is reported for the level
  # it actually reached. Restarting follows the level itself, see restart_on_level/4
  defp check_level(resource, config, current_percentage) do
    level = current_level(current_percentage, config)
    level_changed? = level != config.level

    if level_changed? do
      :ets.insert(
        @watchdog_data,
        {{resource.owner, :config, resource.type}, %{config | level: level}}
      )

      report_level(level, resource, config, current_percentage)
    end

    restart_on_level(level, level_changed?, resource, config)
  end

  # A resource that stays critical is restarted on every check, the usage only comes down once the
  # right application has gone away and the next check picks the next candidate. Terminating
  # DeployEx is the exception, it happens once, the node is already on its way down and repeating
  # it would only re-announce the same shutdown
  defp restart_on_level(
         :critical,
         _level_changed?,
         %{repeat_restart: true} = resource,
         %{enable_restart: true}
       ),
       do: resource.restart.()

  defp restart_on_level(:critical, true, resource, %{enable_restart: true}),
    do: resource.restart.()

  defp restart_on_level(_level, _level_changed?, _resource, _config), do: :ok

  defp current_level(current_percentage, %{
         warning_threshold_percent: warning_threshold_percent,
         restart_threshold_percent: restart_threshold_percent
       }) do
    cond do
      current_percentage >= restart_threshold_percent -> :critical
      current_percentage >= warning_threshold_percent -> :warning
      true -> :ok
    end
  end

  # NOTE: enable_restart decides what DeployEx is allowed to do about a resource, not whether the
  #       resource is worth reporting, so reaching the restart threshold is announced either way
  defp report_level(:critical, resource, %{enable_restart: true} = config, current_percentage) do
    Logger.error(
      "#{resource.label} threshold exceeded: current #{current_percentage}% >= restart #{config.restart_threshold_percent}%. Initiating restart..."
    )

    notify_threshold_exceeded(resource, config, current_percentage, :restart)

    :ok
  end

  defp report_level(:critical, resource, config, current_percentage) do
    Logger.error(
      "#{resource.label} threshold exceeded: current #{current_percentage}% >= restart #{config.restart_threshold_percent}%. Restart is disabled, no action taken."
    )

    notify_threshold_exceeded(resource, config, current_percentage, :no_restart)

    :ok
  end

  defp report_level(:warning, resource, config, current_percentage) do
    Logger.warning(
      "#{resource.label} threshold exceeded: current #{current_percentage}% >= warning #{config.warning_threshold_percent}%."
    )

    notify_threshold_warning(resource, config, current_percentage, :warning)

    :ok
  end

  defp report_level(:ok, resource, config, current_percentage) do
    Logger.warning(
      "#{resource.label} threshold normalized: current #{current_percentage}% < warning #{config.warning_threshold_percent}%."
    )

    notify_threshold_warning(resource, config, current_percentage, :normalized)

    :ok
  end

  defp notify_threshold_exceeded(resource, config, current_percentage, action) do
    Foundation.Notifications.notify("watchdog_threshold_exceeded", %{
      node: resource.node,
      type: resource.type,
      current_percentage: current_percentage,
      restart_threshold_percent: config.restart_threshold_percent,
      action: action
    })
  end

  defp notify_threshold_warning(resource, config, current_percentage, action) do
    Foundation.Notifications.notify("watchdog_threshold_warning", %{
      node: resource.node,
      type: resource.type,
      current_percentage: current_percentage,
      warning_threshold_percent: config.warning_threshold_percent,
      action: action
    })
  end

  defp restart_application(node) do
    %{sname: sname} = Catalog.node_info(node)
    Monitor.restart(sname)

    :ok
  end

  # The host memory is exhausted by the applications DeployEx monitors, so the heaviest one is
  # restarted. There is nothing to restart when DeployEx is not monitoring any application yet
  defp restart_top_memory_consumer(nil) do
    Logger.error("There is no monitored application to restart")

    :ok
  end

  defp restart_top_memory_consumer(node) do
    Logger.error("Restarting #{node}, the application consuming the most memory")

    restart_application(node)
  end

  # DeployEx exhausting its own Beam VM limits can only be cleared by restarting DeployEx itself,
  # restarting a monitored application would not release the atoms, processes or ports leaked here.
  # When installed as a systemd service the termination is followed by an automatic restart
  defp terminate_deployex(terminate_delay) do
    Deployex.force_terminate(terminate_delay)

    :restarting
  end
end
