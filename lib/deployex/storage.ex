defmodule Deployex.Storage do
  @moduledoc """
  This module will provide storage abstraction
  """

  @behaviour Deployex.Storage.Adapter

  @type version_map :: %{version: String.t(), hash: String.t(), pre_commands: list()}

  def default, do: Application.fetch_env!(:deployex, __MODULE__)[:adapter]

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @doc """
  Retrieve the expected current version for the application
  """
  @impl true
  @spec get_current_version_map :: version_map() | nil
  def get_current_version_map do
    storage_map = default().get_current_version_map()

    # Check optional fields
    if storage_map["pre_commands"] == nil do
      Map.put(storage_map, "pre_commands", [])
    else
      storage_map
    end
  end

  @doc """
  Download and unpack the application
  """
  @impl true
  @spec download_and_unpack(integer(), String.t()) ::
          {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  def download_and_unpack(instance, version), do: default().download_and_unpack(instance, version)
end
