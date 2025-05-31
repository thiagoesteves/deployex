defmodule Foundation.Catalog.Version do
  @moduledoc """
  Structure to handle the application version
  """
  @type t :: %__MODULE__{
          version: String.t() | nil,
          hash: String.t() | nil,
          pre_commands: list(),
          name: String.t(),
          sname: String.t(),
          deployment: :full_deployment | :hot_upgrade,
          inserted_at: NaiveDateTime.t() | nil
        }

  @derive Jason.Encoder

  defstruct version: nil,
            hash: nil,
            pre_commands: [],
            name: "",
            sname: "",
            deployment: :full_deployment,
            inserted_at: nil
end
