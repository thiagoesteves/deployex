defmodule Deployer.Release.Local do
  @moduledoc """
    Release adapter used for handling local files
  """

  @behaviour Deployer.Release.Adapter

  require Logger

  ### ==========================================================================
  ### Release Callbacks
  ### ==========================================================================

  @impl true
  def download_version_map(app_name) do
    file_path = "#{bucket()}/versions/#{app_name}/#{env()}/current.json"

    case File.read(file_path) do
      {:ok, data} ->
        Jason.decode!(data)

      reason ->
        Logger.error(
          "Error downloading release version for #{app_name}, reason: #{inspect(reason)}"
        )

        nil
    end
  end

  @impl true
  def download_release(app_name, release_version, download_path) do
    release_name = "#{app_name}-#{release_version}.tar.gz"
    file_path = "#{bucket()}/dist/#{app_name}/#{release_name}"
    dest_path = "#{download_path}/#{release_name}"

    File.cp(file_path, dest_path)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp env, do: Application.get_env(:foundation, :env)

  defp bucket, do: Application.get_env(:deployer, Deployer.Release)[:bucket]
end
