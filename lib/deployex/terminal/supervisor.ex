defmodule Deployex.Terminal.Supervisor do
  @moduledoc false
  use DynamicSupervisor

  alias Deployex.Terminal.Server

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  def new(%Server{} = args) do
    spec = %{id: Server, start: {Server, :start_link, [args]}, restart: :transient}

    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
