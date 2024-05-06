defmodule Deployex.Application do
  @moduledoc false

  use Application

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @impl true
  def start(_type, _args) do
    Deployex.Configuration.init()

    children = [
      Deployex.Deployment,
      Deployex.Monitor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Deployex.Supervisor)
  end
end
