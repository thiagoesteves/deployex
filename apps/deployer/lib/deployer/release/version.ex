defmodule Deployer.Release.Version do
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
