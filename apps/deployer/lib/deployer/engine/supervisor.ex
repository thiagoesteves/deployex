defmodule Deployer.Engine.Supervisor do
  @moduledoc false

  use DynamicSupervisor
  require Logger

  alias Deployer.Engine.Worker

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 20)
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================
  def start_deployment(service) do
    spec = %{
      id: Worker,
      start: {Worker, :start_link, [service]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def stop_deployment(name) do
    child_pid =
      name
      |> String.to_existing_atom()
      |> Process.whereis()

    DynamicSupervisor.terminate_child(__MODULE__, child_pid)
  end
end
