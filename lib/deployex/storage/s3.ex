defmodule Deployex.Storage.S3 do
  @moduledoc """
    Storage adapter used for handling S3 files
  """

  @behaviour Deployex.Storage.Adapter

  alias Deployex.{Configuration, State, Upgrade}

  @region "us-east-2"

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
    path = "versions/#{Configuration.monitored_app()}/#{env()}/current.json"

    bucket()
    |> ExAws.S3.get_object(path)
    |> ExAws.request(region: @region)
    |> case do
      {:ok, %{body: body}} -> Jason.decode!(body)
      _ -> nil
    end
  end

  @doc """
  Download and unpack the application
  """
  @impl true
  @spec download_and_unpack(binary()) :: {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  def download_and_unpack(version) do
    {:ok, download_path} = Briefly.create()

    monitored_app = Configuration.monitored_app()

    s3_path = "dist/#{monitored_app}/#{monitored_app}-#{version}.tar.gz"

    {:ok, :done} =
      bucket()
      |> ExAws.S3.download_file(s3_path, download_path)
      |> ExAws.request(region: @region)

    State.clear_new()

    {"", 0} =
      System.cmd("tar", [
        "-x",
        "-f",
        download_path,
        "-C",
        Configuration.new_path()
      ])

    Upgrade.check(download_path, State.current_version(), version)
  after
    Briefly.cleanup()
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp env, do: Application.get_env(:deployex, :env)
  defp bucket, do: "#{Configuration.monitored_app()}-#{env()}-distribution"
end
