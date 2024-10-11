defmodule Deployex.Release do
  @moduledoc """
  This module will provide release abstraction
  """

  @behaviour Deployex.Release.Adapter

  alias Deployex.Common
  alias Deployex.Storage

  defmodule Version do
    @moduledoc """
    Structure to handle the version structure
    """
    @type t :: %__MODULE__{
            version: String.t() | nil,
            hash: String.t() | nil,
            pre_commands: list()
          }

    @derive Jason.Encoder

    defstruct version: nil,
              hash: nil,
              pre_commands: []
  end

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @doc """
  Retrieve the expected current version for the application
  """
  @impl true
  @spec get_current_version_map :: Deployex.Release.Version.t()
  def get_current_version_map do
    # Check if the manual or automatic mode is enabled
    case Storage.config() do
      %{mode: :automatic} ->
        default().get_current_version_map()

      %{mode: :manual, manual_version: version} ->
        version
    end
    |> Common.cast_schema_fields(%Deployex.Release.Version{})
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
  defp default, do: Application.fetch_env!(:deployex, __MODULE__)[:adapter]
end
