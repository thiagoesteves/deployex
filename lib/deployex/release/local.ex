defmodule Deployex.Release.Local do
  @moduledoc """
    Release adapter used for handling local files
  """

  @behaviour Deployex.Release.Adapter

  alias Deployex.Catalog
  alias Deployex.Status
  alias Deployex.Upgrade

  require Logger

  ### ==========================================================================
  ### Release Callbacks
  ### ==========================================================================

  @doc """
  Retrieve current version
  """
  @impl true
  def get_current_version_map do
    app_name = Catalog.monitored_app_name()

    file_path = "#{bucket()}/versions/#{app_name}/#{env()}/current.json"

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
    app_name = Catalog.monitored_app_name()
    app_lang = Catalog.monitored_app_lang()

    download_path = "#{bucket()}/dist/#{app_name}/#{app_name}-#{version}.tar.gz"

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
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp env, do: Application.get_env(:deployex, :env)

  defp bucket, do: Application.get_env(:deployex, Deployex.Release)[:bucket]
end
