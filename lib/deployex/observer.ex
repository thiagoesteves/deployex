defmodule Deployex.Observer do
  @moduledoc """
  This module will provide observability functions
  """

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @doc """
  Starts monitor service for an specific instance
  """
  def generate() do
    processes = :erlang.processes()

    pid_application = Process.whereis(:application_controller)

    app_info = :application.info()

    running_app = Keyword.get(app_info, :running)

    running_app_group =
      Enum.reduce(running_app, %{}, fn
        {name, pid}, acc when is_pid(pid) ->
          Map.put(acc, name, Process.info(pid) ++ [Process.info(pid, :registered_name)])

        _, acc ->
          acc
      end)

    Map.get(running_app_group, :deployex)
    |> Keyword.get(:group_leader)
    |> lookup(%{exclude_pids: [pid_application], group_leader: nil})
    |> IO.inspect()
    # traverse_process(:iex, running_app_group, exclude_pids: [pid_application])
  end

  # defp traverse_process(application, running_app_group, opts) do
  #   exclude_pids = Keyword.get(opts, :exclude_pids, [])

  #   case Map.get(running_app_group, application) do
  #     [] -> []
  #     process_info ->
  #       links = Keyword.get(process_info, :links) -- exclude_pids
  #   end
  # end
  def lookup(root_pid, %{exclude_pids: exclude_pids} = opts) do
    info = Process.info(root_pid)
    links = Keyword.get(info, :links) -- exclude_pids

    link(root_pid, links, %{ opts | exclude_pids: exclude_pids ++ [root_pid], group_leader: root_pid})
  end

  def link(parent, [port], _opts) when is_port(port) do
    info = Port.info(port)
    print(parent) <> " --- " <> print(port) <> "\n\r"
  end

  def link(parent, [last], %{exclude_pids: exclude_pids, group_leader: group_leader} = opts) when is_pid(last) do
    info = Process.info(last)
    info_links = Keyword.get(info, :links) -- exclude_pids
    info_group_leader = Keyword.get(info, :group_leader)

    if group_leader == info_group_leader do
      case info_links do
        [] -> print(parent) <> " --- " <> print(last) <> "\n\r"
        list -> print(parent) <> " --- " <> link(last, list, %{ opts | exclude_pids: exclude_pids ++ [last]})
      end
    else
      print(parent) <> "\n\r"
    end
  end

  def link(parent, [port | tail], %{exclude_pids: exclude_pids} = opts) when is_port(port) do
    info = Port.info(port)

    print(parent) <>
      " --- " <> print(port) <> "\n\r" <> link(parent, tail, %{ opts | exclude_pids: exclude_pids ++ [parent]})
  end

  def link(parent, [head | tail], %{exclude_pids: exclude_pids, group_leader: group_leader} = opts) when is_pid(head) do
    info = Process.info(head)
    info_links = Keyword.get(info, :links) -- exclude_pids
    info_group_leader = Keyword.get(info, :group_leader)

    if group_leader == info_group_leader do
      case info_links do
        [] -> print(parent) <> " --- " <> print(head) <> "\n\r"
        list -> print(parent) <> " --- " <> link(head, list, %{ opts | exclude_pids: exclude_pids ++ [head]})
      end <> link(parent, tail, %{ opts | exclude_pids: exclude_pids ++ [parent]})
    else
      link(parent, tail, %{ opts | exclude_pids: exclude_pids ++ [parent]})
    end
  end

  defp print(pid) when is_pid(pid) do
    text = "#{inspect(pid)}" |> String.slice(5..-2//1)
    "#{text}"
  end

  defp print(port) when is_port(port) do
    text = "#{inspect(port)}" |> String.slice(6..-2//1)
    "#{text}"
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
