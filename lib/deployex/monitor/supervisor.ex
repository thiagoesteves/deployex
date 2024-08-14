defmodule Deployex.Monitor.Supervisor do
  @moduledoc false

  use DynamicSupervisor
  require Logger

  @default_timeout_app_ready :timer.seconds(30)
  @default_retry_delay_pre_commands :timer.seconds(1)

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
  @spec start_service(integer(), reference(), [Keyword.t()]) ::
          {:ok, pid} | {:error, pid(), :already_started}
  def start_service(instance, deploy_ref, options) do
    timeout_app_ready =
      Keyword.get(options, :timeout_app_ready, @default_timeout_app_ready)

    retry_delay_pre_commands =
      Keyword.get(options, :retry_delay_pre_commands, @default_retry_delay_pre_commands)

    spec = %{
      id: Deployex.Monitor.Application,
      start:
        {Deployex.Monitor.Application, :start_link,
         [
           [
             instance: instance,
             deploy_ref: deploy_ref,
             timeout_app_ready: timeout_app_ready,
             retry_delay_pre_commands: retry_delay_pre_commands
           ]
         ]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @spec stop_service(integer()) :: :ok
  def stop_service(instance) do
    instance
    |> Deployex.Monitor.Application.global_name()
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
