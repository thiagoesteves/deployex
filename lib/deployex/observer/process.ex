defmodule Deployex.Observer.Process do
  @moduledoc """
  Process and pid handling.
  """

  alias Deployex.Observer.Helper

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
    :dictionary,
    :monitored_by,
    :monitors
  ]

  @doc """
  Creates a complete overview of process stats based on the given `pid`.

    iex> alias Deployex.Observer.Process, as: ObserverPort
    ...> kernel_pid = :application_controller.get_master :kernel
    ...> assert %{error_handler: :error_handler, memory: _, relations: %{links: [head, tail]}} = ObserverPort.info(kernel_pid)
    ...> assert %{error_handler: :error_handler, memory: _, relations: _} = ObserverPort.info(head)
    ...> assert %{error_handler: :error_handler, memory: _, relations: _} = ObserverPort.info(tail)
  """
  @spec info(pid :: pid()) :: :error | map
  def info(pid) do
    process_info(pid, @process_full, &structure_full/2)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
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

  defp initial_call(data) do
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
        links: Keyword.get(data, :links, nil),
        monitored_by: Keyword.get(data, :monitored_by, nil),
        monitors: Keyword.get(data, :monitors, nil)
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
