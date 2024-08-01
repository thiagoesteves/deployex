defmodule Deployex.Monitor.Supervisor do
  @moduledoc false

  use DynamicSupervisor
  require Logger

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(init_arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 10)
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================
  @spec start_service(integer(), reference()) :: {:ok, pid} | {:error, pid(), :already_started}
  def start_service(instance, deploy_ref) do
    spec = %{
      id: Deployex.Monitor,
      start: {Deployex.Monitor, :start_link, [[instance: instance, deploy_ref: deploy_ref]]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @spec stop_service(integer()) :: :ok
  def stop_service(instance) do
    instance
    |> Deployex.Monitor.global_name()
    |> :global.whereis_name()
    |> case do
      :undefined ->
        :ok

      child_pid ->
        Deployex.Common.call_gen_server(child_pid, :stop_service)

        DynamicSupervisor.terminate_child(__MODULE__, child_pid)
    end
  end
end
