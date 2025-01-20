defmodule Deployex.Telemetry.Collector do
  @moduledoc """
  GenServer that collects the telemetry data received
  """
  use GenServer
  require Logger

  alias Deployex.Storage

  @metric_key_tables "metric-keys"
  @nodes_table :nodes_list

  @minute_to_milliseconds 60_000

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    Process.flag(:trap_exit, true)

    :ets.new(@nodes_table, [:set, :protected, :named_table])

    {:ok, hostname} = :inet.gethostname()

    Storage.instance_list()
    |> Enum.each(fn instance ->
      node = String.to_atom("#{Storage.sname(instance)}@#{hostname}")
      # Create metric tables for the node
      :ets.new(node, [:set, :protected, :named_table])
      :ets.insert(node, {@metric_key_tables, []})
      # Add the node to the nodes list table to avoid dynamic atom creation
      :ets.insert(@nodes_table, {instance, node})
    end)

    Logger.info("Initialising telemetry collector server")

    {:ok, %{}}
  end

  @impl true
  def handle_cast(
        {:telemetry, %{metrics: metrics, reporter: reporter, measurements: measurements}},
        state
      ) do
    now_to_minute = fn now -> trunc(now / @minute_to_milliseconds) end

    now = System.os_time(:millisecond)
    minute = now_to_minute.(now)

    keys = get_keys_by_node(reporter)

    new_keys =
      Enum.reduce(metrics, [], fn metric, acc ->
        {key, timed_key, data} = prepare_timeseries_data(metric, measurements, now, minute)

        current_data =
          case :ets.lookup(reporter, timed_key) do
            [{_, value}] -> [data | value]
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
      :ets.insert(reporter, {@metric_key_tables, new_keys ++ keys})

      Phoenix.PubSub.broadcast(
        Deployex.PubSub,
        keys_topic(),
        {:metrics_new_keys, reporter, new_keys}
      )
    end

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================
  def collect_data(event) do
    GenServer.cast(__MODULE__, {:telemetry, event})
  end

  def subscribe_for_new_keys do
    Phoenix.PubSub.subscribe(Deployex.PubSub, keys_topic())
  end

  def unsubscribe_for_new_keys do
    Phoenix.PubSub.unsubscribe(Deployex.PubSub, keys_topic())
  end

  def subscribe_for_updates(service, key) do
    Phoenix.PubSub.subscribe(Deployex.PubSub, metrics_topic(service, key))
  end

  def unsubscribe_for_updates(service, key) do
    Phoenix.PubSub.unsubscribe(Deployex.PubSub, metrics_topic(service, key))
  end

  def list_data_by_instance(instance) do
    instance
    |> node_by_instance()
    |> :ets.tab2list()
  end

  def list_data_by_instance_key(instance, key, options \\ []) do
    instance
    |> node_by_instance()
    |> list_data_by_service_key(key, options)
  end

  def list_data_by_service_key(service, key, options \\ [])

  def list_data_by_service_key(service, key, options) when is_binary(service) do
    service
    |> String.to_existing_atom()
    |> list_data_by_service_key(key, options)
  end

  def list_data_by_service_key(service, key, options) when is_atom(service) do
    from = Keyword.get(options, :from, 15)
    order = Keyword.get(options, :order, :asc)

    now_minutes = trunc(System.os_time(:millisecond) / @minute_to_milliseconds)
    from_minutes = now_minutes - from

    result =
      Enum.reduce(from_minutes..now_minutes, [], fn minute, acc ->
        case :ets.lookup(service, "#{key}|#{minute}") do
          [{_, value}] ->
            value ++ acc

          _ ->
            acc
        end
      end)

    if order == :asc, do: Enum.reverse(result), else: result
  end

  def get_keys_by_instance(instance) do
    instance
    |> node_by_instance()
    |> get_keys_by_node()
  end

  def node_by_instance(instance) do
    case :ets.lookup(@nodes_table, instance) do
      [{_, value}] -> value
      _ -> nil
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp get_keys_by_node(node) do
    case :ets.lookup(node, @metric_key_tables) do
      [{_, value}] -> value
      _ -> []
    end
  end

  defp keys_topic, do: "metrics::keys"
  defp metrics_topic(service, key), do: "metrics::#{service}::#{key}"

  ### ==========================================================================
  ### Hanlde data Telemetry.DeployexReporter.Metrics.V1
  ### ==========================================================================
  defp prepare_timeseries_data(%{name: name} = metric, measurements, now, minute)
       when name in ["vm.memory.total"] do
    {name, "#{name}|#{minute}",
     %{timestamp: now, value: metric.value, unit: metric.unit, metadata: measurements}}
  end

  defp prepare_timeseries_data(%{name: name} = metric, _measurements, now, minute) do
    {name, "#{name}|#{minute}",
     %{timestamp: now, value: metric.value, unit: metric.unit, tags: metric.tags}}
  end
end
