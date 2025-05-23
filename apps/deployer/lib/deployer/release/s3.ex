defmodule Deployer.Release.S3 do
  @moduledoc """
    Release adapter used for handling S3 files
  """

  @behaviour Deployer.Release.Adapter

  require Logger

  ### ==========================================================================
  ### Release Callbacks
  ### ==========================================================================

  @impl true
  def download_version_map(app_name) do
    path = "versions/#{app_name}/#{env()}/current.json"

    bucket()
    |> ExAws.S3.get_object(path)
    |> ExAws.request()
    |> case do
      {:ok, %{body: body}} ->
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
    s3_path = "dist/#{app_name}/#{app_name}-#{release_version}.tar.gz"

    case bucket() |> ExAws.S3.download_file(s3_path, download_path) |> ExAws.request() do
      {:ok, :done} ->
        :ok

      reason ->
        reason
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp env, do: Application.get_env(:foundation, :env)

  defp bucket,
    do: Application.get_env(:deployer, Deployer.Release)[:bucket]
end
