defmodule Host.Terminal.Supervisor do
  @moduledoc false
  use DynamicSupervisor

  alias Host.Terminal.Server

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 50, max_seconds: 3)
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  Starts a new supervised Terminal Server
  """
  @spec new(Host.Terminal.t()) :: {:ok, pid} | {:error, pid(), :already_started}
  def new(args) do
    spec = %{id: Server, start: {Server, :start_link, [args]}, restart: :transient}

    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
