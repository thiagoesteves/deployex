defmodule Deployex.Release.Local do
  @moduledoc """
    Release adapter used for handling local files
  """

  @behaviour Deployex.Release.Adapter

  alias Deployex.Status
  alias Deployex.Storage
  alias Deployex.Upgrade

  require Logger

  ### ==========================================================================
  ### CWC Callbacks
  ### ==========================================================================

  @doc """
  Retrieve current version
  """
  @impl true
  def get_current_version_map do
    monitored_app = Storage.monitored_app()

    file_path = "#{bucket()}/versions/#{monitored_app}/#{env()}/current.json"

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
  def download_and_unpack(instance, version) do
    monitored_app = Storage.monitored_app()

    download_path =
      "#{bucket()}/dist/#{monitored_app}/#{monitored_app}-#{version}.tar.gz"

    Status.clear_new(instance)
    new_path = Storage.new_path(instance)

    {"", 0} = System.cmd("tar", ["-x", "-f", download_path, "-C", new_path])

    Upgrade.check(instance, download_path, Status.current_version(instance), version)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp env, do: Application.get_env(:deployex, :env)

  defp bucket, do: Application.get_env(:deployex, Deployex.Release)[:bucket]
end
