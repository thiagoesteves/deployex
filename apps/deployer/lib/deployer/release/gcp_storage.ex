defmodule Deployer.Release.GcpStorage do
  @moduledoc """
    Release adapter used for handling GCP Storage files
  """

  @behaviour Deployer.Release.Adapter

  require Logger

  ### ==========================================================================
  ### Release Callbacks
  ### ==========================================================================

  @impl true
  def download_version_map(app_name) do
    path =
      "https://storage.googleapis.com/#{bucket()}/versions/#{app_name}/#{env()}/current.json"

    :get
    |> Finch.build(path, headers(), [])
    |> Finch.request(Deployer.Finch)
    |> case do
      {:ok, %Finch.Response{body: body}} ->
        Jason.decode!(body)

      reason ->
        Logger.error(
          "Error downloading release version for #{app_name}, reason: #{inspect(reason)}"
        )

        nil
    end
  end

  @impl true
  def download_release(app_name, release_version, download_path) do
    gcp_path =
      "https://storage.googleapis.com/#{bucket()}/dist/#{app_name}/#{app_name}-#{release_version}.tar.gz"

    :get
    |> Finch.build(gcp_path, headers(), [])
    |> Finch.request(Deployer.Finch)
    |> case do
      {:ok, %Finch.Response{body: body}} ->
        File.write!("#{download_path}/#{app_name}-#{release_version}.tar.gz", body)
        :ok

      reason ->
        raise "Error downloading release for #{app_name}, reason: #{inspect(reason)}"
    end

    :ok
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
