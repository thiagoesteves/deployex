defmodule Deployer.Release do
  @moduledoc """
  This module will provide methods to retrieve the release information
  """
  require Logger

  alias Deployer.Upgrade
  alias Foundation.Catalog
  alias Foundation.Common

  @type t :: %__MODULE__{
          current_sname: String.t() | nil,
          current_sname_current_path: String.t() | nil,
          current_sname_new_path: String.t() | nil,
          new_sname: String.t() | nil,
          new_sname_new_path: String.t() | nil,
          current_version: String.t(),
          release_version: String.t()
        }

  defstruct current_sname: nil,
            current_sname_current_path: nil,
            current_sname_new_path: nil,
            new_sname: nil,
            new_sname_new_path: nil,
            current_version: "",
            release_version: ""

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @doc """
  Retrieve the expected current version for the application
  """
  @spec get_current_version_map(String.t()) :: Deployer.Release.Version.t()
  def get_current_version_map(app_name) do
    # Check if the manual or automatic mode is enabled
    case Catalog.config(app_name) do
      %{mode: :automatic} ->
        default().download_version_map(app_name)

      %{mode: :manual, manual_version: version} ->
        version
    end
    |> Common.cast_schema_fields(%Deployer.Release.Version{})
  end

  @doc """
  Download and unpack the application
  """
  @spec download_and_unpack(Deployer.Release.t()) ::
          {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  def download_and_unpack(%Deployer.Release{
        current_sname: current_sname,
        current_sname_current_path: current_sname_current_path,
        current_sname_new_path: current_sname_new_path,
        new_sname: new_sname,
        new_sname_new_path: new_sname_new_path,
        current_version: current_version,
        release_version: release_version
      }) do
    {:ok, download_path} = Briefly.create()

    with %{name: name, language: language} <- Catalog.node_info(current_sname || new_sname),
         :ok <- default().download_release(name, release_version, download_path),
         :ok <-
           provision_new_path(
             name,
             language,
             release_version,
             download_path,
             current_sname_new_path
           ),
         :ok <-
           provision_new_path(name, language, release_version, download_path, new_sname_new_path) do
      if is_nil(current_sname) or is_nil(new_sname) do
        {:ok, :full_deployment}
      else
        %Upgrade.Check{
          sname: current_sname,
          name: name,
          language: language,
          download_path: download_path,
          current_path: current_sname_current_path,
          new_path: current_sname_new_path,
          from_version: current_version,
          to_version: release_version
        }
        |> Upgrade.check()
      end
    else
      reason ->
        Logger.error(
          "Download and unpack error: #{inspect(reason)} current_sname: #{current_sname} new_sname: #{new_sname}"
        )

        {:error, :donwload_process_error}
    end
  after
    Briefly.cleanup()
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]

  defp provision_new_path(name, _language, _release_version, _download_path, new_path)
       when is_nil(name) or is_nil(new_path) do
    :ok
  end

  defp provision_new_path(name, language, release_version, download_path, new_path) do
    # Prepare new folder to receive the release binaries
    File.rm_rf(new_path)
    File.mkdir_p(new_path)

    with {"", 0} <- System.cmd("tar", ["-x", "-f", download_path, "-C", new_path]),
         :ok <- Upgrade.prepare_new_path(name, language, release_version, new_path) do
      :ok
    else
      _ -> {:error, :untar}
    end
  end
end
