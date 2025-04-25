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
  @spec start_service(String.t(), integer(), String.t(), [Keyword.t()]) ::
          {:ok, pid} | {:error, pid(), :already_started}
  def start_service(language, instance, deploy_ref, options) do
    spec = %{
      id: Deployer.Monitor.Application,
      start:
        {Deployer.Monitor.Application, :start_link,
         [
           [
             language: language,
             instance: instance,
             deploy_ref: deploy_ref,
             options: options
           ]
         ]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @spec stop_service(integer()) :: :ok
  def stop_service(instance) do
    instance
    |> Deployer.Monitor.Application.global_name()
    |> Enum.at(0)
    |> :global.whereis_name()
    |> case do
      :undefined ->
        :ok

      child_pid ->
        Foundation.Common.call_gen_server(child_pid, :stop_service)

        DynamicSupervisor.terminate_child(__MODULE__, child_pid)
    end
  end
end
