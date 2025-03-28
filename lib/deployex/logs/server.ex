defmodule Deployex.Logs.Server do
  @moduledoc """
  GenServer that collects the telemetry data received
  """
  use GenServer

  require Logger

  @behaviour Deployex.Logs.Adapter

  alias Deployex.Logs.Data
  alias Deployex.Terminal

  @logs_storage_table :logs_storage_table
  @logs_types "log-types"
  @registry_key "registry-nodes"

  @one_minute_in_milliseconds 60_000
  @retention_data_delete_interval :timer.minutes(1)

  @type t :: %__MODULE__{
          nodes: [atom()],
          node_logs_tables: map(),
          persist_data?: boolean(),
          data_retention_period: nil | non_neg_integer()
        }

  defstruct nodes: [],
            node_logs_tables: %{},
            persist_data?: false,
            data_retention_period: nil

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================
  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)

    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    # Create a general table to store information
    :ets.new(@logs_storage_table, [:set, :protected, :named_table])

    data_retention_period = Keyword.fetch!(args, :data_retention_period)

    persist_data? = fn ->
      if data_retention_period do
        :timer.send_interval(@retention_data_delete_interval, :prune_expired_entries)
        true
      else
        false
      end
    end

    # Subscribe to receive notifications if any node is UP or Down
    :net_kernel.monitor_nodes(true)

    # List all nodes including self()
    nodes = [Node.self()] ++ Node.list()

    {:ok,
     %{
       nodes: nodes,
       persist_data?: persist_data?.(),
       node_logs_tables: Enum.reduce(nodes, %{}, &initialize_log_table(&1, &2)),
       data_retention_period: data_retention_period
     }}
  end

  @impl true
  def handle_info({:terminal_update, event}, state) do
    handle_log_update(event, state)
  end

  def handle_info({:nodeup, node}, state) do
    nodes = state.nodes ++ [node]

    if node |> node_log_table() |> ets_table_exists?() do
      {:noreply, %{state | nodes: nodes}}
    else
      {:noreply,
       %{
         state
         | nodes: nodes,
           node_logs_tables: initialize_log_table(node, state.node_logs_tables)
       }}
    end
  end

  def handle_info(
        {:nodedown, node},
        %{nodes: nodes, persist_data?: persist_data?, node_logs_tables: node_logs_tables} =
          state
      ) do
    node_log_table = Map.get(node_logs_tables, node)
    now = System.os_time(:millisecond)
    minute = unix_to_minutes(now)

    node
    |> get_types_by_node()
    |> Enum.each(fn log_type ->
      if persist_data? do
        timed_log_type_key = log_type_key(log_type, minute)

        data = %Data{
          timestamp: now,
          log: "DeployEx detected node down for node: #{node}"
        }

        # credo:disable-for-lines:2
        current_data =
          case :ets.lookup(node_log_table, timed_log_type_key) do
            [{_, current_list_data}] -> [data | current_list_data]
            _ -> [data]
          end

        :ets.insert(node_log_table, {timed_log_type_key, current_data})

        notify_new_log_data(node, log_type, data)
      end
    end)

    nodes = nodes -- [node]

    {:noreply, %{state | nodes: nodes}}
  end

  def handle_info(
        :prune_expired_entries,
        %{node_logs_tables: tables, data_retention_period: data_retention_period} = state
      ) do
    now_minutes = unix_to_minutes()
    retention_period = trunc(data_retention_period / @one_minute_in_milliseconds)
    deletion_period_to = now_minutes - retention_period - 1
    deletion_period_from = deletion_period_to - 2

    prune_keys = fn key, table ->
      Enum.each(deletion_period_from..deletion_period_to, fn timestamp ->
        :ets.delete(table, log_type_key(key, timestamp))
      end)
    end

    Enum.each(tables, fn {node, table} ->
      node
      |> get_types_by_node()
      |> Enum.each(&prune_keys.(&1, table))
    end)

    {:noreply, state}
  end

  defp handle_log_update(
         %{
           metadata: %{context: :terminal_logs, node: reporter, type: log_key},
           myself: _pid,
           message: message
         },
         %{nodes: nodes, persist_data?: persist_data?, node_logs_tables: node_logs_tables} =
           state
       ) do
    if reporter in nodes do
      node_log_table = Map.get(node_logs_tables, reporter)
      now = System.os_time(:millisecond)
      minute = unix_to_minutes(now)

      log_keys = get_types_by_node(reporter)
      timed_log_type_key = log_type_key(log_key, minute)

      data = %Data{
        timestamp: now,
        log: message
      }

      if persist_data?, do: ets_append_to_list(node_log_table, timed_log_type_key, data)

      notify_new_log_data(reporter, log_key, data)

      if log_key not in log_keys do
        :ets.insert(node_log_table, {@logs_types, [log_key] ++ log_keys})

        Phoenix.PubSub.broadcast(
          Deployex.PubSub,
          new_log_types_topic(),
          {:logs_new_keys, reporter, [log_key]}
        )
      end
    end

    {:noreply, state}
  end

  ### ==========================================================================
  ### ObserverWeb.Telemetry.Adapter implementation
  ### ==========================================================================

  @impl true
  def subscribe_for_new_log_types do
    Phoenix.PubSub.subscribe(Deployex.PubSub, new_log_types_topic())
  end

  @impl true
  def subscribe_for_new_logs(node, key) do
    Phoenix.PubSub.subscribe(Deployex.PubSub, logs_topic(node, key))
  end

  @impl true
  def unsubscribe_for_new_logs(node, key) do
    Phoenix.PubSub.unsubscribe(Deployex.PubSub, logs_topic(node, key))
  end

  @impl true
  def list_data_by_node_log_type(node, type, options \\ [])

  def list_data_by_node_log_type(node, type, options) when is_binary(node) do
    node
    |> String.to_existing_atom()
    |> list_data_by_node_log_type(type, options)
  end

  def list_data_by_node_log_type(node, type, options) when is_atom(node) do
    from = Keyword.get(options, :from, 15)
    order = Keyword.get(options, :order, :asc)

    now_minutes = unix_to_minutes()
    from_minutes = now_minutes - from

    node_table = node_log_table(node)

    result =
      Enum.reduce(from_minutes..now_minutes, [], fn minute, acc ->
        case :ets.lookup(node_table, log_type_key(type, minute)) do
          [{_, value}] ->
            value ++ acc

          _ ->
            acc
        end
      end)

    if order == :asc, do: Enum.reverse(result), else: result
  end

  @impl true
  def get_types_by_node(nil), do: []

  def get_types_by_node(node) do
    node
    |> node_log_table()
    |> ets_lookup_if_exist(@logs_types, [])
  end

  @impl true
  def list_active_nodes do
    ets_lookup_if_exist(@logs_storage_table, @registry_key, [])
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp node_log_table(node), do: String.to_atom("#{node}::deployex-logs")

  defp log_type_key(type, timestamp), do: "#{type}|#{timestamp}"

  defp unix_to_minutes(time \\ System.os_time(:millisecond)),
    do: trunc(time / @one_minute_in_milliseconds)

  defp ets_table_exists?(table_name) do
    case :ets.info(table_name) do
      :undefined -> false
      _info -> true
    end
  end

  defp ets_lookup_if_exist(table, key, default_return) do
    with true <- ets_table_exists?(table),
         [{_, value}] <- :ets.lookup(table, key) do
      value
    else
      _ ->
        default_return
    end
  end

  defp ets_append_to_list(table, key, new_item) do
    case :ets.lookup(table, key) do
      [{^key, current_list_data}] ->
        updated_list = [new_item | current_list_data]
        :ets.insert(table, {key, updated_list})
        updated_list

      [] ->
        # Key doesn't exist yet, create new list with just this item
        :ets.insert(table, {key, [new_item]})
        [new_item]
    end
  end

  # NOTE: PubSub topics
  defp new_log_types_topic, do: "logs::types"
  defp logs_topic(node, type), do: "logs::#{node}::#{type}"

  defp notify_new_log_data(reporter, log_type, data) do
    Phoenix.PubSub.broadcast(
      Deployex.PubSub,
      logs_topic(reporter, log_type),
      {:logs_new_data, reporter, log_type, data}
    )
  end

  defp initialize_log_table(node, current_map) do
    table = node_log_table(node)

    # Create Logs table
    :ets.new(table, [:set, :protected, :named_table])
    :ets.insert(table, {@logs_types, []})

    # Add node the to registry
    ets_append_to_list(@logs_storage_table, @registry_key, node)

    instance = get_instance(node)

    create_terminal = fn log_type ->
      path = log_path(instance, log_type)
      commands = "tail -F -n 0 #{path}"
      options = [:"#{log_type}"]

      File.exists?(path) &&
        Terminal.new(%Terminal{
          instance: instance,
          commands: commands,
          options: options,
          target: self(),
          timeout_session: :infinity,
          metadata: %{context: :terminal_logs, node: node, type: log_type}
        })
    end

    if instance != nil do
      ["stdout", "stderr"]
      |> Enum.each(&create_terminal.(&1))
    end

    Map.put(current_map, node, table)
  end

  defp get_instance(node) do
    [sname, hostname] = String.split("#{node}", ["@"])

    hostname? = fn ->
      {:ok, deployex_hostname} = :inet.gethostname()

      hostname == "#{deployex_hostname}"
    end

    deployex? = sname == "deployex"

    cond do
      hostname?.() and deployex? ->
        0

      hostname?.() and not deployex? ->
        [_name, instance] = String.split(sname, ["-"])
        String.to_integer(instance)

      true ->
        nil
    end
  end

  defp log_path(instance, "stdout"), do: Deployex.Storage.stdout_path(instance)
  defp log_path(instance, "stderr"), do: Deployex.Storage.stderr_path(instance)
end
