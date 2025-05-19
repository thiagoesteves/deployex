defmodule Deployer.Release do
  @moduledoc """
  This module will provide methods to retrieve the release information
  """

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
    case Catalog.config() do
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

    %{name: name, language: language} = Catalog.sname_info(current_sname || new_sname)

    # Download the release file
    default().download_release(name, release_version, download_path)

    if current_sname do
      # Prepare new folder to receive the release binaries
      current_sname_new_path |> File.rm_rf()
      current_sname_new_path |> File.mkdir_p()

      {"", 0} = System.cmd("tar", ["-x", "-f", download_path, "-C", current_sname_new_path])
    end

    if new_sname do
      {"", 0} = System.cmd("tar", ["-x", "-f", download_path, "-C", new_sname_new_path])
    end

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
  after
    Briefly.cleanup()
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
