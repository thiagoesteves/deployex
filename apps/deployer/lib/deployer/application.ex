defmodule Deployer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Deployer.Deployment

  @target Mix.env()

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: Deployer.PubSub},
        Deployer.Monitor.Supervisor,
        {Finch, name: Deployer.Finch},
        {Finch, name: ExAws.Request.Finch}
      ] ++ maybe_add_gen_server() ++ gcp_app_credentials()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Deployer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_gen_server do
    if @target == :test do
      []
    else
      [
        Deployer.Status.Application,
        {Deployment,
         [
           timeout_rollback: Application.fetch_env!(:deployer, Deployment)[:timeout_rollback],
           schedule_interval: Application.fetch_env!(:deployer, Deployment)[:schedule_interval],
           name: Deployment
         ]}
      ]
    end
  end

  defp gcp_app_credentials do
    case Application.get_env(:goth, :file_credentials) do
      nil ->
        []

      file_credentials ->
        source = {:service_account, Jason.decode!(file_credentials)}

        [{Goth, name: Deployer.Goth, source: source}]
    end
  end
end
