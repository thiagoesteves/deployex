defmodule Sentinel.Logs.Server do
  @moduledoc """
  GenServer that collects and store the logs received
  """
  use GenServer

  require Logger

  @behaviour Sentinel.Logs.Adapter

  alias Deployer.Monitor
  alias Foundation.Catalog
  alias Host.Terminal
  alias Sentinel.Logs.Message

  @logs_storage_table :logs_storage_table
  @logs_types "log-types"
  @registry_key "registry-snames"

  @available_log_types ["stdout", "stderr"]

  @one_minute_in_milliseconds 60_000
  @retention_data_delete_interval :timer.minutes(1)

  @type t :: %__MODULE__{
          snames: [String.t()],
          sname_logs_tables: map(),
          persist_data?: boolean(),
          data_retention_period: nil | non_neg_integer()
        }

  defstruct snames: [],
            sname_logs_tables: %{},
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

    # Subscribe to receive a notification every time we have a new deploy
    Monitor.subscribe_new_deploy()

    # List all expected snames within the cluster
    expected_snames = Monitor.list() ++ [self_sname()]

    sname_logs_tables =
      Enum.reduce(expected_snames, %{}, fn sname, acc ->
        case maybe_init_log_table(sname) do
          nil -> acc
          table -> Map.put(acc, sname, table)
        end
      end)

    {:ok,
     %{
       expected_snames: expected_snames,
       persist_data?: persist_data?.(),
       sname_logs_tables: sname_logs_tables,
       data_retention_period: data_retention_period
     }}
  end

  @impl true
  def handle_info(
        {:terminal_update,
         %{
           metadata: %{context: :terminal_logs, sname: reporter, type: log_key},
           source_pid: _pid,
           message: message
         }},
        %{
          expected_snames: expected_snames,
          persist_data?: persist_data?,
          sname_logs_tables: sname_logs_tables
        } =
          state
      ) do
    if reporter in expected_snames do
      sname_log_table = Map.get(sname_logs_tables, reporter)
      now = System.os_time(:millisecond)
      minute = unix_to_minutes(now)

      log_keys = get_types_by_sname(reporter)
      timed_log_type_key = log_type_key(log_key, minute)

      data = %Message{
        timestamp: now,
        log: message
      }

      if persist_data?, do: ets_append_to_list(sname_log_table, timed_log_type_key, data)

      notify_new_log_data(reporter, log_key, data)

      if log_key not in log_keys do
        :ets.insert(sname_log_table, {@logs_types, [log_key] ++ log_keys})
      end
    end

    {:noreply, state}
  end

  def handle_info(
        {:new_deploy, source_node, sname},
        %{sname_logs_tables: sname_logs_tables, expected_snames: expected_snames} = state
      ) do
    with true <- source_node == Node.self(),
         false <- sname in expected_snames,
         table when not is_nil(table) <- maybe_init_log_table(sname) do
      {:noreply,
       %{
         state
         | sname_logs_tables: Map.put(sname_logs_tables, sname, table),
           expected_snames: expected_snames ++ [sname]
       }}
    else
      _error ->
        {:noreply, state}
    end
  end

  def handle_info({:nodeup, _node}, state) do
    # Do Nothing, nodes are static assigned
    {:noreply, state}
  end

  def handle_info(
        {:nodedown, node},
        %{
          persist_data?: persist_data?,
          sname_logs_tables: sname_logs_tables,
          expected_snames: expected_snames
        } =
          state
      ) do
    with %{sname: sname} <- Catalog.node_info(node),
         true <- sname in expected_snames do
      sname_log_table = Map.get(sname_logs_tables, sname)
      now = System.os_time(:millisecond)
      minute = unix_to_minutes(now)

      # Report Node Down at stderr
      log_type = "stderr"

      timed_log_type_key = log_type_key(log_type, minute)

      data = %Message{
        timestamp: now,
        log: "DeployEx detected node down for node: #{node}"
      }

      if persist_data? do
        ets_append_to_list(sname_log_table, timed_log_type_key, data)
      end

      notify_new_log_data(sname, log_type, data)
    end

    {:noreply, state}
  end

  def handle_info(
        :prune_expired_entries,
        %{sname_logs_tables: tables, data_retention_period: data_retention_period} = state
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

    Enum.each(tables, fn {sname, table} ->
      sname
      |> get_types_by_sname()
      |> Enum.each(&prune_keys.(&1, table))
    end)

    {:noreply, state}
  end

  ### ==========================================================================
  ### ObserverWeb.Telemetry.Adapter implementation
  ### ==========================================================================
  @impl true
  def subscribe_for_new_logs(sname, key) do
    Phoenix.PubSub.subscribe(Sentinel.PubSub, logs_topic(sname, key))
  end

  @impl true
  def unsubscribe_for_new_logs(sname, key) do
    Phoenix.PubSub.unsubscribe(Sentinel.PubSub, logs_topic(sname, key))
  end

  @impl true
  def list_data_by_sname_log_type(sname, type, options \\ [])

  def list_data_by_sname_log_type(sname, type, options) do
    from = Keyword.get(options, :from, 15)
    order = Keyword.get(options, :order, :asc)

    now_minutes = unix_to_minutes()
    from_minutes = now_minutes - from

    sname_table = sname_log_table(sname)

    result =
      Enum.reduce(from_minutes..now_minutes, [], fn minute, acc ->
        case :ets.lookup(sname_table, log_type_key(type, minute)) do
          [{_, value}] ->
            value ++ acc

          _ ->
            acc
        end
      end)

    if order == :asc, do: Enum.reverse(result), else: result
  end

  @impl true
  def get_types_by_sname(nil), do: []

  def get_types_by_sname(sname) do
    sname
    |> sname_log_table()
    |> ets_lookup_if_exist(@logs_types, [])
  end

  @impl true
  def list_active_snames do
    ets_lookup_if_exist(@logs_storage_table, @registry_key, [])
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp sname_log_table(sname), do: String.to_atom("deployex-logs::#{sname}")

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
  defp logs_topic(sname, type), do: "logs::#{sname}::#{type}"

  defp notify_new_log_data(reporter, log_type, data) do
    Phoenix.PubSub.broadcast(
      Sentinel.PubSub,
      logs_topic(reporter, log_type),
      {:logs_new_data, reporter, log_type, data}
    )
  end

  defp maybe_init_log_table(sname) do
    create_terminal = fn log_type ->
      path = log_path(sname, log_type)
      commands = "tail -F -n 0 #{path}"
      options = [:"#{log_type}"]

      Terminal.new(%Terminal{
        # node: node,
        commands: commands,
        options: options,
        target: self(),
        timeout_session: :infinity,
        metadata: %{context: :terminal_logs, sname: sname, type: log_type}
      })
    end

    log_files_exist? = fn sname ->
      @available_log_types
      |> Enum.all?(fn log_type ->
        sname
        |> log_path(log_type)
        |> File.exists?()
      end)
    end

    if log_files_exist?.(sname) do
      table = sname_log_table(sname)

      # Create Logs table
      :ets.new(table, [:set, :protected, :named_table])
      :ets.insert(table, {@logs_types, []})

      # Add sname the to registry
      ets_append_to_list(@logs_storage_table, @registry_key, sname)

      Enum.each(@available_log_types, &create_terminal.(&1))

      table
    else
      nil
    end
  end

  defp log_path(sname, "stdout") do
    Catalog.stdout_path(sname) || ""
  end

  defp log_path(sname, "stderr") do
    Catalog.stderr_path(sname) || ""
  end

  defp self_sname do
    [sname, _hostname] = Node.self() |> Atom.to_string() |> String.split(["@"])
    sname
  end
end
