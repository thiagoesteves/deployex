defmodule Host.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: Host.PubSub},
        Host.Terminal.Supervisor
      ] ++ maybe_add_gen_server()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Host.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_gen_server do
    if Mix.env() == :test do
      []
    else
      [Host.Memory.Server]
    end
  end
end
