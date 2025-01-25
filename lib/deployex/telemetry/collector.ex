defmodule Deployex.Telemetry.Collector do
  @moduledoc """
  GenServer that collects the telemetry data received
  """
  use GenServer
  require Logger

  alias Deployex.Storage

  @metric_keys "metric-keys"
  @nodes_table :nodes_list

  @minute_to_milliseconds 60_000
  @data_retention_period_min 1

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(args) do
    :ets.new(@nodes_table, [:set, :protected, :named_table])

    {:ok, hostname} = :inet.gethostname()

    Storage.instance_list()
    |> Enum.each(fn instance ->
      node = String.to_atom("#{Storage.sname(instance)}@#{hostname}")
      # Create metric tables for the node
      :ets.new(node, [:set, :protected, :named_table])
      :ets.insert(node, {@metric_keys, []})
      # Add the node to the nodes list table to improve performance
      :ets.insert(@nodes_table, {instance, node})
    end)

    args
    |> Keyword.get(:data_retention_period_min, :timer.minutes(@data_retention_period_min))
    |> :timer.send_interval(:prune_expired_entries)

    Logger.info("Initialising telemetry collector server")

    {:ok, %{}}
  end

  @impl true
  def handle_cast(
        {:telemetry, %{metrics: metrics, reporter: reporter, measurements: measurements}},
        state
      ) do
    now = System.os_time(:millisecond)
    minute = unix_to_minute(now)

    keys = get_keys_by_node(reporter)

    new_keys =
      Enum.reduce(metrics, [], fn metric, acc ->
        {key, timed_key, data} = prepare_timeseries_data(metric, measurements, now, minute)

        current_data =
          case :ets.lookup(reporter, timed_key) do
            [{_, current_list_data}] -> [data | current_list_data]
            _ -> [data]
          end

        :ets.insert(reporter, {timed_key, current_data})

        Phoenix.PubSub.broadcast(
          Deployex.PubSub,
          metrics_topic(reporter, key),
          {:metrics_new_data, reporter, key, data}
        )

        if key in keys do
          acc
        else
          [key | acc]
        end
      end)

    if new_keys != [] do
      :ets.insert(reporter, {@metric_keys, new_keys ++ keys})

      Phoenix.PubSub.broadcast(
        Deployex.PubSub,
        keys_topic(),
        {:metrics_new_keys, reporter, new_keys}
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:prune_expired_entries, state) do
    now_minutes = unix_to_minute()
    deletion_period_to = now_minutes - @data_retention_period_min - 1
    deletion_period_from = deletion_period_to - 2

    prune_keys = fn node, key ->
      Enum.each(deletion_period_from..deletion_period_to, fn timestamp ->
        :ets.delete(node, metric_key(key, timestamp))
      end)
    end

    Storage.instance_list()
    |> Enum.each(fn instance ->
      node = node_by_instance(instance)

      node
      |> get_keys_by_node()
      |> Enum.each(&prune_keys.(node, &1))
    end)

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================
  @spec collect_data(any()) :: :ok
  def collect_data(event) do
    GenServer.cast(__MODULE__, {:telemetry, event})
  end

  @spec subscribe_for_new_keys() :: :ok | {:error, term}
  def subscribe_for_new_keys do
    Phoenix.PubSub.subscribe(Deployex.PubSub, keys_topic())
  end

  @spec unsubscribe_for_new_keys() :: :ok
  def unsubscribe_for_new_keys do
    Phoenix.PubSub.unsubscribe(Deployex.PubSub, keys_topic())
  end

  @spec subscribe_for_new_data(String.t(), String.t()) :: :ok | {:error, term}
  def subscribe_for_new_data(node, key) do
    Phoenix.PubSub.subscribe(Deployex.PubSub, metrics_topic(node, key))
  end

  @spec unsubscribe_for_new_data(String.t(), String.t()) :: :ok
  def unsubscribe_for_new_data(node, key) do
    Phoenix.PubSub.unsubscribe(Deployex.PubSub, metrics_topic(node, key))
  end

  @spec list_data_by_instance(integer()) :: list()
  def list_data_by_instance(instance) do
    instance
    |> node_by_instance()
    |> :ets.tab2list()
  end

  @spec list_data_by_instance_key(integer(), String.t(), Keyword.t()) :: list()
  def list_data_by_instance_key(instance, key, options \\ []) do
    instance
    |> node_by_instance()
    |> list_data_by_node_key(key, options)
  end

  @spec list_data_by_node_key(atom() | String.t(), String.t(), Keyword.t()) :: list()
  def list_data_by_node_key(node, key, options \\ [])

  def list_data_by_node_key(node, key, options) when is_binary(node) do
    node
    |> String.to_existing_atom()
    |> list_data_by_node_key(key, options)
  end

  def list_data_by_node_key(node, key, options) when is_atom(node) do
    from = Keyword.get(options, :from, 15)
    order = Keyword.get(options, :order, :asc)

    now_minutes = unix_to_minute()
    from_minutes = now_minutes - from

    result =
      Enum.reduce(from_minutes..now_minutes, [], fn minute, acc ->
        case :ets.lookup(node, metric_key(key, minute)) do
          [{_, value}] ->
            value ++ acc

          _ ->
            acc
        end
      end)

    if order == :asc, do: Enum.reverse(result), else: result
  end

  @spec get_keys_by_instance(integer()) :: list()
  def get_keys_by_instance(instance) do
    instance
    |> node_by_instance()
    |> get_keys_by_node()
  end

  @spec node_by_instance(integer()) :: nil | atom()
  def node_by_instance(instance) do
    case :ets.lookup(@nodes_table, instance) do
      [{_, value}] -> value
      _ -> nil
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp metric_key(metric, timestamp), do: "#{metric}|#{timestamp}"

  defp unix_to_minute(time \\ System.os_time(:millisecond)),
    do: trunc(time / @minute_to_milliseconds)

  defp get_keys_by_node(nil), do: []

  defp get_keys_by_node(node) do
    case :ets.lookup(node, @metric_keys) do
      [{_, value}] -> value
      _ -> []
    end
  end

  defp keys_topic, do: "metrics::keys"
  defp metrics_topic(node, key), do: "metrics::#{node}::#{key}"

  ### ==========================================================================
  ### Hanlde data Telemetry.DeployexReporter.Metrics.V1
  ### ==========================================================================
  defp prepare_timeseries_data(%{name: name} = metric, measurements, now, minute)
       when name in ["vm.memory.total"] do
    {name, metric_key(name, minute),
     %{timestamp: now, value: metric.value, unit: metric.unit, metadata: measurements}}
  end

  defp prepare_timeseries_data(%{name: name} = metric, _measurements, now, minute) do
    {name, metric_key(name, minute),
     %{timestamp: now, value: metric.value, unit: metric.unit, tags: metric.tags}}
  end
end
