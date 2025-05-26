defmodule Deployer.Monitor.Supervisor do
  @moduledoc false

  use DynamicSupervisor
  require Logger

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 10)
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================
  def start_service(service) do
    spec = %{
      id: Deployer.Monitor.Application,
      start: {Deployer.Monitor.Application, :start_link, [service]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def list, do: list(format: :string)

  def list(options) do
    format = Keyword.get(options, :format)

    map_list =
      __MODULE__
      |> Supervisor.which_children()
      |> Enum.map(fn {_, pid, :worker, _name} -> pid end)
      |> Enum.reduce([], fn pid, acc ->
        case :rpc.pinfo(pid, :registered_name) do
          {:registered_name, name} ->
            acc ++ [%{name: name, pid: pid}]

          _ ->
            acc
        end
      end)

    cond do
      format == :string ->
        Enum.map(map_list, fn %{name: name} -> Atom.to_string(name) end)

      format == :atom ->
        Enum.map(map_list, fn %{name: name} -> name end)

      true ->
        map_list
    end
  end

  @spec stop_service(String.t() | nil) :: :ok
  def stop_service(nil), do: :ok

  def stop_service(sname) do
    module_name = String.to_existing_atom(sname)

    %{pid: child_pid} = list(format: :map) |> Enum.find(&(&1.name == module_name))

    Foundation.Common.call_gen_server(child_pid, :stop_service)

    DynamicSupervisor.terminate_child(__MODULE__, child_pid)

    :ok
  rescue
    _ ->
      Logger.error("Error while stopping sname: #{sname}")
      :ok
  end
end
