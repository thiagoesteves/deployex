defmodule Host.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import Foundation.Macros

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: Host.PubSub},
        Host.Terminal.Supervisor
      ] ++ application_servers()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Host.Supervisor]
    Supervisor.start_link(children, opts)
  end

  if_not_test do
    defp application_servers do
      [Host.Info.Server]
    end
  else
    defp application_servers, do: []
  end
end
