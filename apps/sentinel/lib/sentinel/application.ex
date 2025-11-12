defmodule Sentinel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import Foundation.Macros

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: Sentinel.PubSub},
        Sentinel.Config.Watcher
      ] ++ application_servers()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sentinel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  if_not_test do
    defp application_servers do
      [
        Sentinel.Watchdog,
        {Sentinel.Logs.Server,
         data_retention_period: Application.fetch_env!(:foundation, :logs_retention_time_ms)}
      ]
    end
  else
    defp application_servers, do: []
  end
end
