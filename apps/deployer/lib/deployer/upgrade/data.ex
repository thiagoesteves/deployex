defmodule Deployer.Upgrade.Execute do
  @moduledoc """
  Structure to handle the upgrade execute data
  """
  @type t :: %__MODULE__{
          node: atom(),
          sname: String.t() | nil,
          name: String.t() | nil,
          language: String.t() | nil,
          current_path: String.t() | nil,
          new_path: String.t() | nil,
          from_version: binary() | charlist() | nil,
          to_version: binary() | charlist() | nil,
          skip_make_permanent: boolean()
        }

  @derive Jason.Encoder

  defstruct node: nil,
            sname: nil,
            name: nil,
            language: nil,
            current_path: nil,
            new_path: nil,
            from_version: nil,
            to_version: nil,
            skip_make_permanent: false
end
