defmodule Deployer.HotUpgrade.Jellyfish do
  @moduledoc """
  Handles parsing and representation of Jellyfish appup metadata files.

  Jellyfish generates JSON metadata files (`jellyfish.json`) during the release
  process that describe hot-upgrade transitions. This module provides utilities
  to read and decode those files into structured data.
  """
  @type t :: %__MODULE__{
          name: String.t() | nil,
          type: String.t() | nil,
          from: String.t() | nil,
          to: String.t() | nil
        }

  defstruct [:name, :type, :from, :to]

  @default_type "project"

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  Decodes a Jellyfish metadata JSON file into a struct.

  Reads and parses a `.appup.json` file, extracting upgrade information
  such as application name, upgrade type, and version transition details.
  """
  @spec decode_jellyfish_file(file :: String.t()) :: __MODULE__.t()
  def decode_jellyfish_file(file) do
    appup_info = file |> File.read!() |> Jason.decode!()

    %__MODULE__{
      name: appup_info["name"],
      type: appup_info["type"] || @default_type,
      from: appup_info["from"],
      to: appup_info["to"]
    }
  end
end
