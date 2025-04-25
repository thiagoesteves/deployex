defmodule Deployer.Release.GcpStorage do
  @moduledoc """
    Release adapter used for handling GCP Storage files
  """

  @behaviour Deployer.Release.Adapter

  alias Deployer.Status
  alias Deployer.Upgrade
  alias Foundation.Catalog

  require Logger

  ### ==========================================================================
  ### Release Callbacks
  ### ==========================================================================

  @doc """
  Retrieve current version
  """
  @impl true
  def get_current_version_map do
    path =
      "https://storage.googleapis.com/#{bucket()}/versions/#{Catalog.monitored_app_name()}/#{env()}/current.json"

    :get
    |> Finch.build(path, headers(), [])
    |> Finch.request(Deployer.Finch)
    |> case do
      {:ok, %Finch.Response{body: body}} -> Jason.decode!(body)
      _ -> nil
    end
  end

  @doc """
  Download and unpack the application
  """
  @impl true
  def download_and_unpack(instance, version) do
    {:ok, download_path} = Briefly.create()

    app_name = Catalog.monitored_app_name()
    app_lang = Catalog.monitored_app_lang()

    gcp_path =
      "https://storage.googleapis.com/#{bucket()}/dist/#{app_name}/#{app_name}-#{version}.tar.gz"

    :get
    |> Finch.build(gcp_path, headers(), [])
    |> Finch.request(Deployer.Finch)
    |> case do
      {:ok, %Finch.Response{body: body}} ->
        File.write!(download_path, body)

      reason ->
        raise "Error while downloading release, reason: #{inspect(reason)}"
    end

    Status.clear_new(instance)
    new_path = Catalog.new_path(instance)

    {"", 0} = System.cmd("tar", ["-x", "-f", download_path, "-C", new_path])

    Upgrade.check(
      instance,
      app_name,
      app_lang,
      download_path,
      Status.current_version(instance),
      version
    )
  after
    Briefly.cleanup()
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp env, do: Application.get_env(:foundation, :env)

  defp headers do
    token = Goth.fetch!(Deployer.Goth)
    [{"Authorization", "Bearer #{token.token}"}]
  end

  defp bucket,
    do: Application.get_env(:deployer, Deployer.Release)[:bucket]
end
