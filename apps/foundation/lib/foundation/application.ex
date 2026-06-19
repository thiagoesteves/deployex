defmodule Foundation.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  ### ==========================================================================
  ### Callback Functions
  ### ==========================================================================

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: Foundation.PubSub},
        {Finch, name: Foundation.Finch},
        Foundation.Catalog.Local,
        Foundation.Certificates.Manager.Supervisor,
        Foundation.Certificate,
        Foundation.Notifications.Supervisor
      ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Foundation.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _pid} = response ->
        Foundation.Notifications.initialize_notification_manager()
        response

      {:error, reason} = response ->
        Logger.error("Error Initializing Deployer Application reason: #{inspect(reason)}")
        response
    end
  end
end
