defmodule Deployer.Upgrade.Data do
  @moduledoc """
  Structure to handle the upgrade data
  """
  @type t :: %__MODULE__{
          node: atom(),
          sname: String.t() | nil,
          name: String.t() | nil,
          language: String.t() | nil,
          current_path: String.t() | nil,
          new_path: String.t() | nil,
          from_version: binary() | charlist() | nil,
          to_version: binary() | charlist() | nil
        }

  @derive Jason.Encoder

  defstruct node: nil,
            sname: nil,
            name: nil,
            language: nil,
            current_path: nil,
            new_path: nil,
            from_version: nil,
            to_version: nil
end
