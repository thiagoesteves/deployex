defmodule Deployex.Observer.Process do
  @moduledoc """
  Process and pid handling.
  """

  alias Deployex.Observer.Helper

  @process_summary [
    :registered_name,
    :initial_call,
    :memory,
    :reductions,
    :current_function,
    :message_queue_len,
    :dictionary
  ]

  @process_full [
    :registered_name,
    :priority,
    :trap_exit,
    :initial_call,
    :current_function,
    :message_queue_len,
    :error_handler,
    :group_leader,
    :links,
    :memory,
    :total_heap_size,
    :heap_size,
    :stack_size,
    :min_heap_size,
    :garbage_collection,
    :status,
    :dictionary
  ]

  @process_meta [
    :initial_call,
    :current_function,
    :status,
    :dictionary
  ]

  @doc ~S"""
  Creates a complete overview of process stats based on the given `pid`.

  Including but not limited to:
    - `id`, the process pid
    - `name`, the registered name or `nil`.
    - `init`, initial function or name.
    - `current`, current function.
    - `memory`, the total amount of memory used by the process.
    - `reductions`, the amount of reductions.
    - `message_queue_length`, the amount of unprocessed messages for the process.,
  """
  @spec info(pid :: pid | list | binary | integer | {integer, integer, integer}) :: :error | map
  def info(pid) do
    process_info(pid, @process_full, &structure_full/2)
  end

  @doc """
  Retreives a list of process summaries.

  Every summary contains:
    - `id`, the process pid.
    - `name`, the registered name or `nil`.
    - `init`, initial function or name.
    - `current`, current function.
    - `memory`, the total amount of memory used by the process.
    - `reductions`, the amount of reductions.
    - `message_queue_length`, the amount of unprocessed messages for the process.
  """
  @spec list :: list(map)
  def list do
    :erlang.processes()
    |> Enum.map(&summary/1)
  end

  @doc ~S"""
  Creates formatted meta information about the process based on the given `pid`.

  The information contains:
    - `init`, initial function or name.
    - `current`, current function.
    - `status`, process status.

  """
  @spec meta(pid :: pid) :: map
  def meta(pid),
    do: pid |> process_info(@process_meta, &structure_meta/2)

  @doc ~S"""
  Creates formatted summary about the process based on the given `pid`.

  Every summary contains:
    - `id`, the process pid.
    - `name`, the registered name or `nil`.
    - `init`, initial function or name.
    - `current`, current function.
    - `memory`, the total amount of memory used by the process.
    - `reductions`, the amount of reductions.
    - `message_queue_length`, the amount of unprocessed messages for the process.

  """
  @spec summary(pid :: pid) :: map
  def summary(pid),
    do: pid |> process_info(@process_summary, &structure_summary/2)

  # Helpers

  defp process_info(nil, _, _), do: :error

  defp process_info(pid, information, structurer) do
    case :rpc.pinfo(pid, information) do
      :undefined -> :error
      data -> structurer.(data, pid)
    end
  end

  defp process_status_module(pid) do
    {:status, ^pid, {:module, class}, _} = :sys.get_status(pid, 100)
    class
  catch
    _, _ -> :unknown
  end

  defp state(pid) do
    :sys.get_state(pid, 100)
  catch
    _, _ -> :unknown
  end

  @doc false
  @spec initial_call(data :: keyword) :: {atom, atom, integer} | atom
  def initial_call(data) do
    dictionary_init =
      data
      |> Keyword.get(:dictionary, [])
      |> Keyword.get(:"$initial_call", nil)

    case dictionary_init do
      nil ->
        Keyword.get(data, :initial_call, nil)

      call ->
        call
    end
  end

  # Structurers

  defp structure_summary(data, pid) do
    process_name =
      case Keyword.get(data, :registered_name, []) do
        [] -> nil
        name -> name
      end

    %{
      pid: pid,
      name: process_name,
      init: Helper.format_function(initial_call(data)),
      current: Helper.format_function(Keyword.get(data, :current_function, nil)),
      memory: Keyword.get(data, :memory, 0),
      reductions: Keyword.get(data, :reductions, 0),
      message_queue_length: Keyword.get(data, :message_queue_len, 0)
    }
  end

  defp structure_full(data, pid) do
    gc = Keyword.get(data, :garbage_collection, [])
    dictionary = Keyword.get(data, :dictionary)

    %{
      pid: pid,
      registered_name: Keyword.get(data, :registered_name, nil),
      priority: Keyword.get(data, :priority, :normal),
      trap_exit: Keyword.get(data, :trap_exit, false),
      message_queue_len: Keyword.get(data, :message_queue_len, 0),
      error_handler: Keyword.get(data, :error_handler, :none),
      relations: %{
        group_leader: Keyword.get(data, :group_leader, nil),
        ancestors: Keyword.get(dictionary, :"$ancestors", []),
        links: Keyword.get(data, :links, nil)
      },
      memory: %{
        total: Keyword.get(data, :memory, 0),
        stack_and_heap: Keyword.get(data, :total_heap_size, 0),
        heap_size: Keyword.get(data, :heap_size, 0),
        stack_size: Keyword.get(data, :stack_size, 0),
        gc_min_heap_size: Keyword.get(gc, :min_heap_size, 0),
        gc_full_sweep_after: Keyword.get(gc, :fullsweep_after, 0)
      },
      meta: structure_meta(data, pid),
      state: to_string(:io_lib.format("~tp", [state(pid)]))
    }
  end

  defp structure_meta(data, pid) do
    init = initial_call(data)

    class =
      case init do
        {:supervisor, _, _} -> :supervisor
        {:application_master, _, _} -> :application
        _ -> process_status_module(pid)
      end

    %{
      init: Helper.format_function(init),
      current: Helper.format_function(Keyword.get(data, :current_function)),
      status: Keyword.get(data, :status),
      class: class
    }
  end
end
