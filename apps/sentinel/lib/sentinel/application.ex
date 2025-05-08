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
        {Phoenix.PubSub, name: Sentinel.PubSub}
      ] ++ application_servers()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sentinel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  if_not_test do
    defp logs_config, do: Application.fetch_env!(:sentinel, Sentinel.Logs)

    defp application_servers do
      [
        Sentinel.Watchdog,
        {Sentinel.Logs.Server, logs_config()}
      ]
    end
  else
    defp application_servers, do: []
  end
end
