defmodule Deployex.Storage.Local do
  @moduledoc """
    Storage adapter used for handling local files
  """

  @behaviour Deployex.Storage.Adapter

  alias Deployex.{AppConfig, AppStatus, Upgrade}

  require Logger

  ### ==========================================================================
  ### CWC Callbacks
  ### ==========================================================================

  @doc """
  Retrieve current version
  """
  @impl true
  @spec get_current_version_map() :: Deployex.Storage.version_map() | nil
  def get_current_version_map do
    monitored_app = AppConfig.monitored_app()

    file_path = "/tmp/#{monitored_app}/versions/#{monitored_app}/#{env()}/current.json"

    case File.read(file_path) do
      {:ok, data} ->
        Jason.decode!(data)

      {:error, reason} ->
        Logger.error("Invalid version map at: #{file_path} reason: #{reason}")
        nil
    end
  end

  @doc """
  Download and unpack the application
  """
  @impl true
  @spec download_and_unpack(integer(), binary()) ::
          {:error, :invalid_from_version} | {:ok, :full_deployment | :hot_upgrade}
  def download_and_unpack(instance, version) do
    monitored_app = AppConfig.monitored_app()

    storage_path =
      "dist/#{monitored_app}/#{monitored_app}-#{version}.tar.gz"

    download_path = "/tmp/#{monitored_app}/" <> storage_path

    AppStatus.clear_new(instance)
    new_path = AppConfig.new_path(instance)

    {"", 0} = System.cmd("tar", ["-x", "-f", download_path, "-C", new_path])

    Upgrade.check(instance, download_path, AppStatus.current_version(instance), version)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp env, do: Application.get_env(:deployex, :env)
end
