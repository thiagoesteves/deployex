defmodule Deployex.Release.S3 do
  @moduledoc """
    Release adapter used for handling S3 files
  """

  @behaviour Deployex.Release.Adapter

  alias Deployex.{AppConfig, Status, Upgrade}

  require Logger

  ### ==========================================================================
  ### CWC Callbacks
  ### ==========================================================================

  @doc """
  Retrieve current version
  """
  @impl true
  def get_current_version_map do
    path = "versions/#{AppConfig.monitored_app()}/#{env()}/current.json"

    bucket()
    |> ExAws.S3.get_object(path)
    |> ExAws.request()
    |> case do
      {:ok, %{body: body}} -> Jason.decode!(body)
      _ -> nil
    end
  end

  @doc """
  Download and unpack the application
  """
  @impl true
  def download_and_unpack(instance, version) do
    {:ok, download_path} = Briefly.create()

    monitored_app = AppConfig.monitored_app()

    s3_path = "dist/#{monitored_app}/#{monitored_app}-#{version}.tar.gz"

    {:ok, :done} =
      bucket()
      |> ExAws.S3.download_file(s3_path, download_path)
      |> ExAws.request()

    Status.clear_new(instance)
    new_path = AppConfig.new_path(instance)

    {"", 0} = System.cmd("tar", ["-x", "-f", download_path, "-C", new_path])

    Upgrade.check(instance, download_path, Status.current_version(instance), version)
  after
    Briefly.cleanup()
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp env, do: Application.get_env(:deployex, :env)

  defp bucket do
    # NOTE: Cloud structures use "-" instead of "_".
    "#{AppConfig.monitored_app()}-#{env()}-distribution" |> String.replace("_", "-")
  end
end
