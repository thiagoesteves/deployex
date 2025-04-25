defmodule Deployer.Release do
  @moduledoc """
  This module will provide release abstraction
  """

  @behaviour Deployer.Release.Adapter

  alias Foundation.Catalog
  alias Foundation.Common

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @doc """
  Retrieve the expected current version for the application
  """
  @impl true
  @spec get_current_version_map :: Deployer.Release.Version.t()
  def get_current_version_map do
    # Check if the manual or automatic mode is enabled
    case Catalog.config() do
      %{mode: :automatic} ->
        default().get_current_version_map()

      %{mode: :manual, manual_version: version} ->
        version
    end
    |> Common.cast_schema_fields(%Deployer.Release.Version{})
  end

  @doc """
  Download and unpack the application
  """
  @impl true
  @spec download_and_unpack(integer(), String.t()) ::
          {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  def download_and_unpack(instance, version), do: default().download_and_unpack(instance, version)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
