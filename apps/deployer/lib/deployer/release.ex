defmodule Deployer.Release do
  @moduledoc """
  This module will provide methods to retrieve the release information
  """

  alias Deployer.Upgrade
  alias Foundation.Catalog
  alias Foundation.Common

  @type t :: %__MODULE__{
          current_node: node() | nil,
          new_node: node() | nil,
          current_version: String.t(),
          release_version: String.t()
        }

  defstruct current_node: nil,
            new_node: nil,
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
        current_node: current_node,
        new_node: new_node,
        current_version: current_version,
        release_version: release_version
      }) do
    {:ok, download_path} = Briefly.create()

    %{name_string: app_name, language: language} = Catalog.node_info(current_node || new_node)

    # Download the release file
    default().download_release(app_name, release_version, download_path)

    if current_node do
      # Prepare new folder to receive the release binaries
      current_node |> Catalog.new_path() |> File.rm_rf()
      current_node |> Catalog.new_path() |> File.mkdir_p()

      new_path = Catalog.new_path(current_node)
      {"", 0} = System.cmd("tar", ["-x", "-f", download_path, "-C", new_path])
    end

    if new_node do
      new_path = Catalog.new_path(new_node)
      {"", 0} = System.cmd("tar", ["-x", "-f", download_path, "-C", new_path])
    end

    if is_nil(current_node) or is_nil(new_node) do
      {:ok, :full_deployment}
    else
      Upgrade.check(
        current_node,
        app_name,
        language,
        download_path,
        current_version,
        release_version
      )
    end
  after
    Briefly.cleanup()
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
