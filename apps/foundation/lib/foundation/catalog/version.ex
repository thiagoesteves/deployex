defmodule Foundation.Catalog.Version do
  @moduledoc """
  Structure to handle the application version
  """
  @type t :: %__MODULE__{
          version: String.t() | nil,
          hash: String.t() | nil,
          pre_commands: list(),
          deployment: :full_deployment | :hot_upgrade,
          deploy_ref: String.t() | nil,
          inserted_at: NaiveDateTime.t()
        }

  @derive Jason.Encoder

  defstruct version: nil,
            hash: nil,
            pre_commands: [],
            deployment: :full_deployment,
            deploy_ref: nil,
            inserted_at: nil
end
