defmodule Deployex.Release.GcpStorage do
  @moduledoc """
    Release adapter used for handling GCP Storage files
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
    path =
      "https://storage.googleapis.com/#{bucket()}/versions/#{Storage.monitored_app_name()}/#{env()}/current.json"

    :get
    |> Finch.build(path, headers(), [])
    |> Finch.request(Deployex.Finch)
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

    monitored_app = Storage.monitored_app_name()

    gcp_path =
      "https://storage.googleapis.com/#{bucket()}/dist/#{monitored_app}/#{monitored_app}-#{version}.tar.gz"

    :get
    |> Finch.build(gcp_path, headers(), [])
    |> Finch.request(Deployex.Finch)
    |> case do
      {:ok, %Finch.Response{body: body}} ->
        File.write!(download_path, body)

      reason ->
        raise "Error while downloading release, reason: #{inspect(reason)}"
    end

    Status.clear_new(instance)
    new_path = Storage.new_path(instance)

    {"", 0} = System.cmd("tar", ["-x", "-f", download_path, "-C", new_path])

    Upgrade.check(instance, download_path, Status.current_version(instance), version)
  after
    Briefly.cleanup()
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp env, do: Application.get_env(:deployex, :env)

  defp headers do
    token = Goth.fetch!(Deployex.Goth)
    [{"Authorization", "Bearer #{token.token}"}]
  end

  defp bucket,
    do: Application.get_env(:deployex, Deployex.Release)[:bucket]
end
