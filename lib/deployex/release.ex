defmodule Deployex.Release do
  @moduledoc """
  This module will provide release abstraction
  """

  @behaviour Deployex.Release.Adapter

  alias Deployex.Status

  @type version_map :: %{version: String.t(), hash: String.t(), pre_commands: list()}

  defstruct version: nil,
            hash: nil,
            pre_commands: []

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
    # Check if the manual or automatic mode is enabled
    case Status.state() do
      {:ok, %Status{mode: :automatic}} ->
        default().get_current_version_map()

      {:ok, %Status{mode: :manual, manual_version: version}} ->
        version
    end
    |> optional_fields()
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
  defp optional_fields(nil), do: nil

  defp optional_fields(release_map) do
    if release_map["pre_commands"] == nil do
      Map.put(release_map, "pre_commands", [])
    else
      release_map
    end
  end
end
