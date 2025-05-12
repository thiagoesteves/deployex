defmodule Deployer.Release.S3 do
  @moduledoc """
    Release adapter used for handling S3 files
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
    path = "versions/#{Catalog.monitored_app_name()}/#{env()}/current.json"

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
  def download_and_unpack(node, version) do
    {:ok, download_path} = Briefly.create()

    app_name = Catalog.monitored_app_name()
    app_lang = Catalog.monitored_app_lang()

    s3_path = "dist/#{app_name}/#{app_name}-#{version}.tar.gz"

    {:ok, :done} =
      bucket()
      |> ExAws.S3.download_file(s3_path, download_path)
      |> ExAws.request()

    Status.clear_new(node)
    new_path = Catalog.new_path(node)

    {"", 0} = System.cmd("tar", ["-x", "-f", download_path, "-C", new_path])

    Upgrade.check(
      node,
      app_name,
      app_lang,
      download_path,
      Status.current_version(node),
      version
    )
  after
    Briefly.cleanup()
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp env, do: Application.get_env(:foundation, :env)

  defp bucket,
    do: Application.get_env(:deployer, Deployer.Release)[:bucket]
end
