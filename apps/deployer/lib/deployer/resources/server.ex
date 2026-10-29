defmodule Deployer.Resources.Server do
  @moduledoc """
  Samples each running instance every few seconds and keeps the result in a protected ETS table.

  A node that does not answer an RPC within the timeout is skipped for that sample, and its entry is removed,
  so a hung node delays the loop by at most one timeout.
  """
  use GenServer

  alias Deployer.Monitor
  alias Deployer.Resources
  alias Deployer.Resources.Limit
  alias Foundation.Catalog
  alias Foundation.Rpc
  alias Host.Commander

  @sample_interval :timer.seconds(5)
  @rpc_timeout 1_000
  @history_minutes 60
  @limits [
    process: {:process_count, :process_limit},
    port: {:port_count, :port_limit},
    atom: {:atom_count, :atom_limit}
  ]

  ### ==========================================================================
  ### GenServer callbacks
  ### ==========================================================================
  def start_link(args \\ []) do
    name = Keyword.get(args, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.put(args, :name, name), name: name)
  end

  @impl true
  def init(args) do
    name = Keyword.fetch!(args, :name)
    :ets.new(name, [:set, :protected, :named_table])

    interval = Keyword.get(args, :sample_interval, @sample_interval)
    schedule(interval)

    {:ok, %{table: name, interval: interval, instances: %{}}}
  end

  @impl true
  def handle_info(:sample, %{table: table, interval: interval} = state) do
    state = sample(state)

    # Entries for instances that stopped, or did not answer this time, are removed
    for {sname, _resources} <- :ets.tab2list(table), not Map.has_key?(state.instances, sname) do
      :ets.delete(table, sname)
    end

    schedule(interval)
    {:noreply, state}
  end

  # Samples now and replies when the table holds the result
  @impl true
  def handle_call(:sample, _from, state), do: {:reply, :ok, sample(state)}

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  Returns the last sample of an instance, or nil when it has none or the server does not run.
  """
  @spec get(sname :: String.t(), name :: atom()) :: Resources.t() | nil
  def get(sname, name \\ __MODULE__) do
    with table when table != :undefined <- :ets.whereis(name),
         [{^sname, resources}] <- :ets.lookup(table, sname) do
      resources
    else
      _ -> nil
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp schedule(:manual), do: :ok
  defp schedule(interval), do: Process.send_after(self(), :sample, interval)

  defp sample(%{table: table, instances: previous} = state) do
    now_ms = System.monotonic_time(:millisecond)
    minute = div(System.os_time(:second), 60)

    instances =
      running_instances()
      |> Enum.reduce(%{}, fn {sname, node}, acc ->
        case sample_instance(node, Map.get(previous, sname), now_ms, minute) do
          {:ok, instance} -> Map.put(acc, sname, instance)
          :error -> acc
        end
      end)

    memory = read_memory(instances)
    cores = :erlang.system_info(:logical_processors_online)
    sampled_at = DateTime.utc_now(:second)

    Enum.each(instances, fn {sname, instance} ->
      resources = %Resources{
        sname: sname,
        cpu: cpu_percent(instance, Map.get(previous, sname), cores),
        memory: Map.get(memory, instance.os_pid),
        process: limit(instance, :process, minute),
        port: limit(instance, :port, minute),
        atom: limit(instance, :atom, minute),
        sampled_at: sampled_at
      }

      :ets.insert(table, {sname, resources})
    end)

    %{state | instances: instances}
  end

  defp running_instances do
    Enum.reduce(Monitor.list(), [], fn sname, acc ->
      with %{status: :running} <- Monitor.state(sname),
           %{node: node} <- Catalog.node_info(sname) do
        [{sname, node} | acc]
      else
        _ -> acc
      end
    end)
  end

  defp sample_instance(node, previous, now_ms, minute) do
    with {:ok, {runtime_ms, _since_last_call}} <- rpc(node, :erlang, :statistics, [:runtime]),
         {:ok, os_pid} <- os_pid(node, previous),
         {:ok, counts} <- counts(node) do
      history = if previous && previous.node == node, do: previous.history, else: []

      {:ok,
       %{
         node: node,
         os_pid: os_pid,
         runtime_ms: runtime_ms,
         at_ms: now_ms,
         counts: counts,
         history: add_history(history, minute, counts)
       }}
    end
  end

  # The OS pid of an instance does not change while its node stays the same
  defp os_pid(node, %{node: node, os_pid: os_pid}), do: {:ok, os_pid}

  defp os_pid(node, _previous) do
    with {:ok, os_pid} <- rpc(node, :os, :getpid, []) do
      {:ok, os_pid |> to_string() |> String.to_integer()}
    end
  end

  defp counts(node) do
    @limits
    |> Enum.flat_map(fn {_kind, {count, limit}} -> [count, limit] end)
    |> Enum.reduce_while({:ok, %{}}, fn key, {:ok, acc} ->
      case rpc(node, :erlang, :system_info, [key]) do
        {:ok, value} when is_integer(value) -> {:cont, {:ok, Map.put(acc, key, value)}}
        _ -> {:halt, :error}
      end
    end)
  end

  defp rpc(node, module, function, args) do
    case Rpc.call(node, module, function, args, @rpc_timeout) do
      {:badrpc, _reason} -> :error
      value -> {:ok, value}
    end
  end

  # The minute series keeps one entry per minute, newest first, for the last hour
  defp add_history([{minute, _counts} | rest], minute, counts), do: [{minute, counts} | rest]

  defp add_history(history, minute, counts) do
    [
      {minute, counts}
      | Enum.take_while(history, fn {at, _} -> minute - at <= @history_minutes end)
    ]
  end

  # CPU time of all the BEAM's threads over the wall time since the last sample, as a share of every core
  defp cpu_percent(
         %{node: node, runtime_ms: runtime_ms, at_ms: at_ms},
         %{node: node} = previous,
         cores
       )
       when at_ms > previous.at_ms and runtime_ms >= previous.runtime_ms do
    round((runtime_ms - previous.runtime_ms) / ((at_ms - previous.at_ms) * cores) * 100)
  end

  defp cpu_percent(_instance, _previous, _cores), do: nil

  defp limit(%{counts: counts, history: history}, kind, minute) do
    {count_key, limit_key} = Keyword.fetch!(@limits, kind)
    count = Map.fetch!(counts, count_key)
    limit = Map.fetch!(counts, limit_key)

    {change_percent, change_minutes} =
      case List.last(history) do
        {at, %{^count_key => old}} when at < minute and old > 0 ->
          {round((count - old) / old * 100), minute - at}

        _ ->
          {nil, nil}
      end

    %Limit{
      count: count,
      limit: limit,
      percent: if(limit > 0, do: trunc(count / limit * 100), else: 0),
      change_percent: change_percent,
      change_minutes: change_minutes
    }
  end

  # One ps call for every instance. The resident memory comes in kilobytes
  defp read_memory(instances) when map_size(instances) == 0, do: %{}

  defp read_memory(instances) do
    pids = instances |> Map.values() |> Enum.map_join(",", & &1.os_pid)

    case Commander.run("ps -o pid=,rss= -p #{pids}", [:sync, :stdout]) do
      {:ok, output} -> parse_ps(output)
      {:error, output} when is_list(output) -> parse_ps(output)
      _ -> %{}
    end
  end

  defp parse_ps(output) do
    output
    |> Keyword.get(:stdout, [])
    |> Enum.join()
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case line |> String.split() |> Enum.map(&Integer.parse/1) do
        [{pid, ""}, {rss_kb, ""}] -> Map.put(acc, pid, rss_kb * 1024)
        _ -> acc
      end
    end)
  end
end
