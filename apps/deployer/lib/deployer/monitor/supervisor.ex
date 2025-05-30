defmodule Deployer.Monitor.Supervisor do
  @moduledoc false

  use DynamicSupervisor
  require Logger

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(%{name: name} = init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: name)
  end

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
  def create_monitor_supervisor(name) do
    supervisor_name = supervisor_name(name)

    spec = %{
      id: supervisor_name,
      start: {__MODULE__, :start_link, [%{name: supervisor_name}]},
      type: :supervisor,
      restart: :permanent
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def start_service(%{name: name} = service) do
    spec = %{
      id: Deployer.Monitor.Application,
      start: {Deployer.Monitor.Application, :start_link, [service]},
      restart: :transient
    }

    name
    |> supervisor_name()
    |> DynamicSupervisor.start_child(spec)
  end

  def list, do: list(format: :string)

  def list(options) do
    accumulate_pid_name = fn pid, acc ->
      case :erlang.process_info(pid, :registered_name) do
        {:registered_name, name} ->
          acc ++ [%{name: name, pid: pid}]

        _ ->
          acc
      end
    end

    map_list =
      __MODULE__
      |> Supervisor.which_children()
      |> Enum.map(fn {_, pid, :supervisor, _name} -> pid end)
      |> Enum.reduce([], &accumulate_pid_name.(&1, &2))
      |> Enum.reduce([], fn %{name: supervisor}, acc ->
        workers_list =
          supervisor
          |> Supervisor.which_children()
          |> Enum.map(fn {_, pid, :worker, _name} -> pid end)
          |> Enum.reduce([], &accumulate_pid_name.(&1, &2))

        workers_list ++ acc
      end)

    format = Keyword.get(options, :format)

    cond do
      format == :string ->
        Enum.map(map_list, fn %{name: name} -> Atom.to_string(name) end)

      format == :atom ->
        Enum.map(map_list, fn %{name: name} -> name end)

      true ->
        map_list
    end
  end

  def stop_service(name, sname) when is_nil(name) or is_nil(sname), do: :ok

  def stop_service(name, sname) do
    module_name = String.to_existing_atom(sname)

    %{pid: child_pid} = list(format: :map) |> Enum.find(&(&1.name == module_name))

    Foundation.Common.call_gen_server(child_pid, :stop_service)

    name
    |> supervisor_name()
    |> DynamicSupervisor.terminate_child(child_pid)

    :ok
  rescue
    _ ->
      Logger.error("Error while stopping sname: #{sname}")
      :ok
  end

  defp supervisor_name(name), do: String.to_atom("#{__MODULE__}.#{Macro.camelize(name)}")
end
