defmodule Deployer.Application do
  @moduledoc false

  use Application

  import Foundation.Macros

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: Deployer.PubSub},
        Deployer.Monitor.Supervisor,
        {Finch, name: Deployer.Finch},
        {Finch, name: ExAws.Request.Finch}
      ] ++ application_servers() ++ gcp_app_credentials()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Deployer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  if_not_test do
    alias Deployer.Deployment
    alias Foundation.Catalog

    defp deployment_servers do
      Enum.map(Catalog.applications(), fn %{name: name} = application ->
        timeout_rollback = Application.fetch_env!(:deployer, Deployment)[:timeout_rollback]
        schedule_interval = Application.fetch_env!(:deployer, Deployment)[:schedule_interval]
        ghosted_version_list = Deployer.Status.ghosted_version_list(name)

        {Deployment,
         [
           struct(
             %Deployment{
               timeout_rollback: timeout_rollback,
               schedule_interval: schedule_interval,
               ghosted_version_list: ghosted_version_list
             },
             application
           )
         ]}
      end)
    end

    defp application_servers do
      [Deployer.Status.Application] ++ deployment_servers()
    end
  else
    defp application_servers, do: []
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
