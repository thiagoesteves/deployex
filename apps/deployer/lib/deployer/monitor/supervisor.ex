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
  @spec start_service(node(), String.t(), non_neg_integer(), [Keyword.t()]) ::
          {:ok, pid} | {:error, pid(), :already_started}
  def start_service(node, language, port, options) do
    spec = %{
      id: Deployer.Monitor.Application,
      start:
        {Deployer.Monitor.Application, :start_link,
         [
           [
             language: language,
             port: port,
             node: node,
             options: options
           ]
         ]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @spec list() :: list()
  def list do
    Enum.reduce(:global.registered_names(), [], fn
      %{module: Deployer.Monitor.Application, node: node}, acc -> acc ++ [node]
      _, acc -> acc
    end)
  end

  @spec stop_service(node() | nil) :: :ok
  def stop_service(nil), do: :ok

  def stop_service(node) do
    node
    |> Deployer.Monitor.Application.global_name()
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
