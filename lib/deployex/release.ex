defmodule Deployex.Release do
  @moduledoc """
  This module will provide release abstraction
  """

  @behaviour Deployex.Release.Adapter

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
    populate_optional_fields(default().get_current_version_map())
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
  defp populate_optional_fields(nil), do: nil

  defp populate_optional_fields(release_map) do
    if release_map["pre_commands"] == nil do
      Map.put(release_map, "pre_commands", [])
    else
      release_map
    end
  end
end
